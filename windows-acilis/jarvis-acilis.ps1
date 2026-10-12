# J.A.R.V.I.S. acilis ekrani
# Oturum acilinca Edge'i tam ekran (kiosk) acar, animasyonu oynatir, bitince kapatir.
$ErrorActionPreference = 'SilentlyContinue'
$dir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$html = Join-Path $dir 'jarvis-acilis.html'
$url  = ([System.Uri]$html).AbsoluteUri
$prof = Join-Path $env:LOCALAPPDATA 'JarvisAcilis\EdgeProfil'

$edge = @(
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { Start-Process $html; exit }

# Masaustu yerlessin
Start-Sleep -Seconds 2

$argList = @(
  '--kiosk', "`"$url`"", '--edge-kiosk-type=fullscreen',
  "--user-data-dir=`"$prof`"",
  '--no-first-run', '--no-default-browser-check',
  '--autoplay-policy=no-user-gesture-required'
)
Start-Process -FilePath $edge -ArgumentList $argList

function Get-JarvisEdge {
  Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*JarvisAcilis*' }
}

# Sayfa bitince basligini JARVIS_DONE yapar; en gec 25 sn sonra yine kapatilir.
$deadline = (Get-Date).AddSeconds(25)
Start-Sleep -Seconds 3
while ((Get-Date) -lt $deadline) {
  $ids = @(Get-JarvisEdge | ForEach-Object { $_.ProcessId })
  if ($ids.Count -eq 0) { break }
  $done = Get-Process -Id $ids | Where-Object { $_.MainWindowTitle -like '*JARVIS_DONE*' }
  if ($done) { break }
  Start-Sleep -Milliseconds 300
}
Get-JarvisEdge | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
