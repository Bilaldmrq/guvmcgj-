# J.A.R.V.I.S. acilis ekranini kurar: dosyalari kopyalar, Baslangic klasorune kisayol ekler.
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $env:LOCALAPPDATA 'JarvisAcilis'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Path (Join-Path $src 'jarvis-acilis.html'), (Join-Path $src 'jarvis-acilis.ps1') -Destination $dst -Force

$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'JARVIS Acilis.lnk'
$sh  = New-Object -ComObject WScript.Shell
$s   = $sh.CreateShortcut($lnk)
$s.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$s.Arguments  = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $dst 'jarvis-acilis.ps1') + '"'
$s.WorkingDirectory = $dst
$s.WindowStyle = 7
$s.Description = 'J.A.R.V.I.S. acilis ekrani'
$s.Save()

Write-Host ''
Write-Host '  J.A.R.V.I.S. acilisi kuruldu.' -ForegroundColor Cyan
Write-Host "  Kisayol: $lnk"
Write-Host '  Her oturum acilisinda otomatik oynayacak.'
Write-Host ''
Write-Host '  Simdi bir kez deneniyor... (atlamak icin herhangi bir tusa bas)'
& (Join-Path $dst 'jarvis-acilis.ps1')
