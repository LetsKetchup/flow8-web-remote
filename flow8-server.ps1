# FLOW 8 Web Remote - local mini server (started by start-mixer.bat)
#
# HTTP on http://localhost:8000/ (only this PC):
#   /<file>      static files from this folder
#   /languages   list of the files in languages/
#   /ping, /bye  heartbeat of the mixer page; the server stops when the page is closed
#   /audio       level/spectrum data from the Firefox feeder (flow8-audio-feeder.html)
#   /xair        relay for the X-Air emulation (see below)
#
# UDP port 10024 in the local network (X-Air remote protocol, OSC):
#   The mixer page answers like a Behringer XR12, so X-Air remote apps can control the FLOW 8.
#   This server does not interpret anything. It only passes packets on:
#   GET  /xair  waits up to 1 s and returns received packets, one per line: "<from ip:port> <local ip> <base64>"
#   POST /xair  sends packets, one per line: "<to ip:port> <base64>"

$root = $PSScriptRoot
$url = 'http://localhost:8000/flow8-mixer-ble.html'
function Open-Page { try { Start-Process 'msedge' $url } catch { Start-Process $url } }

$http = New-Object Net.HttpListener
$http.Prefixes.Add('http://localhost:8000/')
try { $http.Start() } catch { Open-Page; exit }      # already running: just open the page
Open-Page

$udp = $null
try {
  $udp = New-Object Net.Sockets.UdpClient 10024
  $udp.EnableBroadcast = $true
} catch { $udp = $null }                              # port busy: everything else still works

$audio = ''
$queue = New-Object System.Collections.Generic.List[string]
$localIp = @{}                                        # cache: remote ip -> own ip in that network
$poll = $null; $pollEnd = Get-Date
$deadline = (Get-Date).AddSeconds(90)

function Get-LocalIp($remote) {
  if ($localIp.ContainsKey($remote)) { return $localIp[$remote] }
  $ip = '127.0.0.1'
  try {
    $s = New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Dgram, [Net.Sockets.ProtocolType]::Udp)
    $s.Connect([Net.IPAddress]::Parse($remote), 10024); $ip = $s.LocalEndPoint.Address.ToString(); $s.Close()
  } catch {}
  $localIp[$remote] = $ip; return $ip
}
function Send-Text($ctx, [string]$text, [string]$type) {
  $b = [Text.Encoding]::UTF8.GetBytes($text)
  $ctx.Response.ContentType = $type
  $ctx.Response.OutputStream.Write($b, 0, $b.Length)
  $ctx.Response.Close()
}
function Answer-Poll {
  $text = ($queue -join "`n"); $queue.Clear()
  $c = $script:poll; $script:poll = $null
  try { Send-Text $c $text 'text/plain; charset=utf-8' } catch {}
}

while ($true) {
  $task = $http.GetContextAsync()
  while (-not $task.Wait(15)) {
    if ((Get-Date) -gt $deadline) { $http.Stop(); if ($udp) { $udp.Close() }; exit }
    if ($udp) {
      while ($udp.Available -gt 0) {
        $ep = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
        try { $data = $udp.Receive([ref]$ep) } catch { break }
        $from = $ep.Address.ToString()
        if ($queue.Count -lt 2000) { $queue.Add($from + ':' + $ep.Port + ' ' + (Get-LocalIp $from) + ' ' + [Convert]::ToBase64String($data)) }
      }
    }
    if ($poll -and ($queue.Count -gt 0 -or (Get-Date) -gt $pollEnd)) { Answer-Poll }
  }
  $c = $task.Result
  $p = [Uri]::UnescapeDataString($c.Request.Url.LocalPath).TrimStart('/')
  if ($p -eq 'ping') { $deadline = (Get-Date).AddSeconds(90); $c.Response.StatusCode = 204; $c.Response.Close() }
  elseif ($p -eq 'bye') { $deadline = (Get-Date).AddSeconds(8); $c.Response.StatusCode = 204; $c.Response.Close() }
  elseif ($p -eq 'languages') {
    $names = (Get-ChildItem (Join-Path $root 'languages') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join "`n"
    Send-Text $c ([string]$names) 'text/plain; charset=utf-8'
  }
  elseif ($p -eq 'audio') {
    if ($c.Request.HttpMethod -eq 'POST') { $audio = (New-Object IO.StreamReader($c.Request.InputStream)).ReadToEnd(); $c.Response.StatusCode = 204; $c.Response.Close() }
    elseif ($audio -eq '') { $c.Response.StatusCode = 204; $c.Response.Close() }
    else { Send-Text $c $audio 'application/json' }
  }
  elseif ($p -eq 'xair') {
    if (-not $udp) { $c.Response.StatusCode = 503; $c.Response.Close() }
    elseif ($c.Request.HttpMethod -eq 'POST') {
      $body = (New-Object IO.StreamReader($c.Request.InputStream)).ReadToEnd()
      foreach ($line in $body -split "`n") {
        $parts = $line.Trim() -split ' '
        if ($parts.Count -ne 2) { continue }
        $i = $parts[0].LastIndexOf(':')
        try {
          $ep = New-Object Net.IPEndPoint([Net.IPAddress]::Parse($parts[0].Substring(0, $i)), [int]$parts[0].Substring($i + 1))
          $data = [Convert]::FromBase64String($parts[1])
          [void]$udp.Send($data, $data.Length, $ep)
        } catch {}
      }
      $c.Response.StatusCode = 204; $c.Response.Close()
    }
    else {
      if ($poll) { Answer-Poll }                      # only one waiting request at a time
      $poll = $c; $pollEnd = (Get-Date).AddSeconds(1)
      if ($queue.Count -gt 0) { Answer-Poll }
    }
  }
  else {
    $f = Join-Path $root $p
    if (($p -notlike '*..*') -and (Test-Path $f -PathType Leaf)) {
      $b = [IO.File]::ReadAllBytes($f)
      $c.Response.Headers.Add('Cache-Control', 'no-store')
      if ($f -like '*.html') { $c.Response.ContentType = 'text/html; charset=utf-8' }
      elseif ($f -like '*.txt') { $c.Response.ContentType = 'text/plain; charset=utf-8' }
      elseif ($f -like '*.js') { $c.Response.ContentType = 'text/javascript' }
      else { $c.Response.ContentType = 'application/octet-stream' }
      $c.Response.OutputStream.Write($b, 0, $b.Length)
    } else { $c.Response.StatusCode = 404 }
    $c.Response.Close()
  }
}
