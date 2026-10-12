# J.A.R.V.I.S. acilis ekranini tamamen kaldirir.
$ErrorActionPreference = 'SilentlyContinue'
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'JARVIS Acilis.lnk'
Remove-Item $lnk -Force
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
  Where-Object { $_.CommandLine -like '*JarvisAcilis*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 1
Remove-Item (Join-Path $env:LOCALAPPDATA 'JarvisAcilis') -Recurse -Force
Write-Host ''
Write-Host '  J.A.R.V.I.S. acilisi kaldirildi.' -ForegroundColor Cyan
