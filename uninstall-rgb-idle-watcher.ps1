$ErrorActionPreference = 'SilentlyContinue'
$taskName = 'RGB Idle Watcher'

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false

$startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'RGB Idle Watcher.lnk'
Remove-Item -LiteralPath $startupShortcut -Force
$startupVbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'RGB Idle Watcher.vbs'
Remove-Item -LiteralPath $startupVbs -Force

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*rgb-idle-watcher.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Write-Host "Removed: $taskName"
