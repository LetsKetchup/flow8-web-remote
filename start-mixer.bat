@echo off
rem Startet den lokalen Mini-Server (flow8-server.ps1) und oeffnet den Mixer in Edge.
rem Der Server beendet sich selbst, wenn die Mixer-Seite geschlossen wird.
if not "%~1"=="min" (
  start "FLOW 8 Server" /min "%~f0" min
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0flow8-server.ps1"
