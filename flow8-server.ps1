# FLOW 8 Web Remote - local mini server (started by start-mixer.bat)
#
# HTTP on port 8000 (own small web server, no admin rights needed):
#   From this PC (localhost) everything is allowed.
#   From other devices in the network (phone, tablet) only with the access code, if the mixer page requires one
#   (Security window). A correct ?code=... sets a cookie, so the code is only needed once per device.
#
#   /<file>      static files from this folder
#   /languages   list of the files in languages/
#   /ping, /bye  heartbeat of the mixer page on the PC; the server stops when that page is closed   (PC only)
#   /audio       level/spectrum data from the Firefox feeder (flow8-audio-feeder.html)               (PC only)
#   /r/...       relay between the mixer page on the PC and phones/tablets:
#                POST /r/sec   (PC)     "<on 1|0> <code required 1|0> <code>": remote control on/off, code yes/no
#                GET  /r/info  (PC)     own IP addresses and number of connected devices
#                POST /r/state (PC)     latest mixer state (JSON); GET /r/state?v=N (device) waits up to 10 s for a newer one (header X-Ver)
#                POST /r/cmd   (device) commands, one JSON per line; GET /r/cmd (PC) waits up to 1 s for commands
#                POST /r/audio (PC)     levels and spectra; GET /r/audio (device), or GET /r/audio?ev=1 as a continuous
#                                       event stream (text/event-stream): every new frame is pushed at once

$root = $PSScriptRoot
$url = 'http://localhost:8000/flow8-mixer-ble.html'
function Open-Page { try { Start-Process 'msedge' $url } catch { Start-Process $url } }

$tcp = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Any, 8000)
try { $tcp.Start() } catch { Open-Page; exit }      # already running: just open the page
Open-Page

$conns = New-Object System.Collections.Generic.List[object]   # open connections, each: client, stream, data, since
$audio = ''; $raudio = ''
$cmds = New-Object System.Collections.Generic.List[string]    # commands from devices for the page
$state = ''; $stateVer = 0
$secOn = $false; $secRequired = $true; $secCode = ''          # until the page reports its setting: devices are refused
$devices = @{}                                                 # device ip -> last seen
$waitCmd = $null; $waitCmdEnd = Get-Date
$waitState = New-Object System.Collections.Generic.List[object]   # each: conn, ver, end
$sse = New-Object System.Collections.Generic.List[object]         # open audio event streams (devices)
$sseBeat = Get-Date
$deadline = (Get-Date).AddSeconds(90)

# Own IPv4 addresses straight from the network adapters (no DNS lookup: that can block the server for seconds), cached for 30 s
$ownIps = ''; $ownIpsAt = [datetime]::MinValue
function Get-OwnIps {
  if (((Get-Date) - $script:ownIpsAt).TotalSeconds -lt 30) { return $script:ownIps }
  $list = @()
  try {
    foreach ($ni in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
      if ($ni.OperationalStatus -ne 'Up' -or $ni.NetworkInterfaceType -eq 'Loopback') { continue }
      foreach ($ua in $ni.GetIPProperties().UnicastAddresses) {
        $a = $ua.Address
        if ($a.AddressFamily -eq 'InterNetwork' -and -not [Net.IPAddress]::IsLoopback($a) -and -not $a.ToString().StartsWith('169.254.')) { $list += $a.ToString() }
      }
    }
  } catch {}
  $script:ownIps = ($list | Select-Object -Unique) -join ' '; $script:ownIpsAt = Get-Date
  return $script:ownIps
}
function Send-Reply($cn, [int]$status, [string]$type, $body, [string]$extra) {
  if ($body -is [string]) { $body = [Text.Encoding]::UTF8.GetBytes($body) }
  if ($null -eq $body) { $body = [byte[]]@() }
  $reason = @{ 200 = 'OK'; 204 = 'No Content'; 403 = 'Forbidden'; 404 = 'Not Found'; 503 = 'Service Unavailable' }[$status]
  $head = "HTTP/1.1 $status $reason`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n$extra`r`n"
  try {
    $h = [Text.Encoding]::ASCII.GetBytes($head)
    $cn.stream.Write($h, 0, $h.Length); if ($body.Length) { $cn.stream.Write($body, 0, $body.Length) }
    $cn.stream.Flush()
  } catch {}
  try { $cn.client.Close() } catch {}
}
function Answer-Cmd { $t = ($cmds -join "`n"); $cmds.Clear(); $c = $script:waitCmd; $script:waitCmd = $null; Send-Reply $c 200 'text/plain; charset=utf-8' $t '' }
function Send-Sse([string]$t) {
  $b = [Text.Encoding]::UTF8.GetBytes($t)
  foreach ($c in $sse.ToArray()) { try { $c.stream.Write($b, 0, $b.Length); $c.stream.Flush() } catch { try { $c.client.Close() } catch {}; [void]$sse.Remove($c) } }
}
function Get-Query($q, $name) { if ($q -match "(^|[?&])$name=([^&]*)") { return [Uri]::UnescapeDataString($Matches[2]) } return '' }

function Handle($cn, $method, $target, $headers, [byte[]]$body) {
  $path = $target; $q = ''
  $i = $target.IndexOf('?'); if ($i -ge 0) { $path = $target.Substring(0, $i); $q = $target.Substring($i) }
  $p = [Uri]::UnescapeDataString($path).TrimStart('/')
  $ip = $cn.client.Client.RemoteEndPoint.Address
  $isLocal = [Net.IPAddress]::IsLoopback($ip)
  $extra = ''
  if (-not $isLocal) {
    $cookie = ''; if ($headers['cookie'] -match 'f8code=([A-Za-z0-9]+)') { $cookie = $Matches[1] }
    $given = Get-Query $q 'code'
    if (-not $secOn) { Send-Reply $cn 403 'text/html; charset=utf-8' '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><body style="font-family:sans-serif;background:#111;color:#eee;padding:24px"><h2>FLOW 8 Web Remote</h2><p>Remote control is switched off. Switch it on in the Remote window of the mixer page on the PC.</p><p>Die Fernsteuerung ist ausgeschaltet. Im Fenster &bdquo;Remote&ldquo; der Mixerseite am PC einschalten.</p></body>' "X-F8: off`r`n"; return }
    $ok = (-not $secRequired) -or ($secCode -ne '' -and ($given -eq $secCode -or $cookie -eq $secCode))
    if (-not $ok) { Send-Reply $cn 403 'text/html; charset=utf-8' '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><body style="font-family:sans-serif;background:#111;color:#eee;padding:24px"><h2>FLOW 8 Web Remote</h2><p>Access code required. Open the address shown in the Remote window of the mixer page on the PC.</p><p>Zugangscode erforderlich. Adresse aus dem Fenster &bdquo;Remote&ldquo; der Mixerseite am PC &ouml;ffnen.</p></body>' "X-F8: code`r`n"; return }
    if ($given -ne '' -and $given -eq $secCode) { $extra = "Set-Cookie: f8code=$secCode; Path=/; SameSite=Strict`r`n" }
    $devices[$ip.ToString()] = Get-Date
    if ($p -in @('ping', 'bye', 'audio', 'r/sec', 'r/info') -or ($p -eq 'r/state' -and $method -eq 'POST') -or ($p -eq 'r/cmd' -and $method -eq 'GET') -or ($p -eq 'r/audio' -and $method -eq 'POST')) {
      Send-Reply $cn 403 'text/plain' 'PC only' ''; return
    }
  }
  $text = [Text.Encoding]::UTF8.GetString($body)
  switch ($p) {
    'ping' { $script:deadline = (Get-Date).AddSeconds(90); Send-Reply $cn 204 'text/plain' $null ''; return }
    'bye' { $script:deadline = (Get-Date).AddSeconds(8); Send-Reply $cn 204 'text/plain' $null ''; return }
    'languages' {
      $names = (Get-ChildItem (Join-Path $root 'languages') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join "`n"
      Send-Reply $cn 200 'text/plain; charset=utf-8' ([string]$names) $extra; return
    }
    'audio' {
      if ($method -eq 'POST') { $script:audio = $text; Send-Reply $cn 204 'text/plain' $null '' }
      elseif ($audio -eq '') { Send-Reply $cn 204 'text/plain' $null '' }
      else { Send-Reply $cn 200 'application/json' $audio '' }
      return
    }
    'r/sec' {
      $a = $text.Trim() -split ' '
      $script:secOn = ($a[0] -eq '1'); $script:secRequired = ($a.Count -lt 2 -or $a[1] -ne '0'); $script:secCode = $(if ($a.Count -gt 2) { $a[2] } else { '' })
      if (-not $secOn) {          # switched off: end the open streams and waiting requests of the devices at once
        foreach ($c in $sse.ToArray()) { try { $c.client.Close() } catch {} }; $sse.Clear()
        foreach ($w in $waitState.ToArray()) { Send-Reply $w.conn 403 'text/plain' 'off' "X-F8: off`r`n" }; $waitState.Clear()
      }
      Send-Reply $cn 204 'text/plain' $null ''; return
    }
    'r/info' {
      $now = Get-Date; $n = @($devices.Values | Where-Object { ($now - $_).TotalSeconds -lt 15 }).Count
      Send-Reply $cn 200 'text/plain; charset=utf-8' ("$n`n" + (Get-OwnIps)) ''; return
    }
    'r/state' {
      if ($method -eq 'POST') {
        $script:state = $text; $script:stateVer++
        foreach ($w in $waitState.ToArray()) { Send-Reply $w.conn 200 'application/json; charset=utf-8' $state "X-Ver: $stateVer`r`n"; [void]$waitState.Remove($w) }
        Send-Reply $cn 204 'text/plain' $null ''; return
      }
      $v = 0; [void][int]::TryParse((Get-Query $q 'v'), [ref]$v)
      if ($state -ne '' -and $stateVer -ne $v) { Send-Reply $cn 200 'application/json; charset=utf-8' $state ("X-Ver: $stateVer`r`n" + $extra); return }
      $waitState.Add([pscustomobject]@{ conn = $cn; end = (Get-Date).AddSeconds(10) }); return
    }
    'r/cmd' {
      if ($method -eq 'POST') { foreach ($line in $text -split "`n") { if ($line.Trim() -ne '' -and $cmds.Count -lt 5000) { $cmds.Add($line.Trim()) } }; Send-Reply $cn 204 'text/plain' $null ''; return }
      if ($script:waitCmd) { Answer-Cmd }
      $script:waitCmd = $cn; $script:waitCmdEnd = (Get-Date).AddSeconds(1)
      if ($cmds.Count -gt 0) { Answer-Cmd }
      return
    }
    'r/audio' {
      if ($method -eq 'GET' -and (Get-Query $q 'ev') -eq '1') {
        $h = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/event-stream`r`nCache-Control: no-store`r`nConnection: keep-alive`r`n$extra`r`nretry: 1000`n`n")
        try { $cn.stream.WriteTimeout = 300; $cn.stream.Write($h, 0, $h.Length); $cn.stream.Flush(); $sse.Add($cn) } catch { try { $cn.client.Close() } catch {} }
        return
      }
      if ($method -eq 'POST') { $script:raudio = $text; Send-Sse ("data: " + $text + "`n`n"); Send-Reply $cn 204 'text/plain' $null '' }
      elseif ($raudio -eq '') { Send-Reply $cn 204 'text/plain' $null $extra }
      else { Send-Reply $cn 200 'application/json' $raudio $extra }
      return
    }
  }
  if ($p -eq '') { $p = 'flow8-mixer-ble.html' }
  $f = Join-Path $root $p
  if (($p -notlike '*..*') -and (Test-Path $f -PathType Leaf)) {
    $type = 'application/octet-stream'
    if ($f -like '*.html') { $type = 'text/html; charset=utf-8' } elseif ($f -like '*.txt') { $type = 'text/plain; charset=utf-8' } elseif ($f -like '*.png') { $type = 'image/png' } elseif ($f -like '*.pdf') { $type = 'application/pdf' }
    Send-Reply $cn 200 $type ([IO.File]::ReadAllBytes($f)) $extra
  } else { Send-Reply $cn 404 'text/plain' 'not found' '' }
}

# Reads one complete request from a connection; returns $true when it was handled
function Try-Request($cn) {
  try {
    while ($cn.client.Available -gt 0) { $buf = New-Object byte[] 65536; $n = $cn.stream.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $cn.data.Write($buf, 0, $n) }
  } catch { try { $cn.client.Close() } catch {}; return $true }
  $all = $cn.data.ToArray()
  $txt = [Text.Encoding]::ASCII.GetString($all)
  $he = $txt.IndexOf("`r`n`r`n"); if ($he -lt 0) { return $false }
  $lines = $txt.Substring(0, $he) -split "`r`n"
  $first = $lines[0] -split ' '
  if ($first.Count -lt 2) { try { $cn.client.Close() } catch {}; return $true }
  $headers = @{}
  foreach ($l in ($lines | Select-Object -Skip 1)) { $k = $l.IndexOf(':'); if ($k -gt 0) { $headers[$l.Substring(0, $k).Trim().ToLower()] = $l.Substring($k + 1).Trim() } }
  $len = 0; if ($headers['content-length']) { [void][int]::TryParse($headers['content-length'], [ref]$len) }
  if ($all.Length -lt $he + 4 + $len) { return $false }
  $body = New-Object byte[] $len; if ($len -gt 0) { [Array]::Copy($all, $he + 4, $body, 0, $len) }
  Handle $cn $first[0] $first[1] $headers $body
  return $true
}

while ($true) {
  try {
    $now = Get-Date
    if ($now -gt $deadline) { $tcp.Stop(); exit }
    $busy = $false
    while ($tcp.Pending()) {
      $cl = $tcp.AcceptTcpClient(); $cl.NoDelay = $true
      $conns.Add([pscustomobject]@{ client = $cl; stream = $cl.GetStream(); data = New-Object IO.MemoryStream; since = $now }); $busy = $true
    }
    foreach ($cn in $conns.ToArray()) {
      if ($cn.client.Available -gt 0 -or $cn.data.Length -gt 0) {
        if (Try-Request $cn) { [void]$conns.Remove($cn); $busy = $true }
      } elseif (($now - $cn.since).TotalSeconds -gt 10) { try { $cn.client.Close() } catch {}; [void]$conns.Remove($cn) }
    }
    if ($waitCmd -and ($cmds.Count -gt 0 -or $now -gt $waitCmdEnd)) { Answer-Cmd }
    foreach ($w in $waitState.ToArray()) { if ($now -gt $w.end) { Send-Reply $w.conn 204 'text/plain' $null ''; [void]$waitState.Remove($w) } }
    if ($sse.Count -gt 0 -and ($now - $sseBeat).TotalSeconds -gt 10) { $sseBeat = $now; Send-Sse ": k`n`n" }    # keeps the streams alive, drops dead ones
    if (-not $busy) {        # wait until something arrives (new connection or request data), at most 20 ms
      $rd = New-Object System.Collections.ArrayList
      [void]$rd.Add($tcp.Server)
      foreach ($c in $conns) { [void]$rd.Add($c.client.Client) }
      try { [Net.Sockets.Socket]::Select($rd, $null, $null, 20000) } catch { Start-Sleep -Milliseconds 5 }
      # readable but nothing to read = the browser closed this connection: drop it (else Select would wake up again at once)
      foreach ($c in $conns.ToArray()) {
        if ($rd.Contains($c.client.Client) -and $c.client.Available -eq 0 -and $c.data.Length -eq 0) { try { $c.client.Close() } catch {}; [void]$conns.Remove($c) }
      }
    }
  } catch { Write-Host ('Error: ' + $_.Exception.Message + ' (line ' + $_.InvocationInfo.ScriptLineNumber + ')'); Start-Sleep -Milliseconds 20 }   # one bad request must not stop the server
}
