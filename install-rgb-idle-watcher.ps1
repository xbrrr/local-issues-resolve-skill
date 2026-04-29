$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$watcherScript = Join-Path $scriptRoot 'rgb-idle-watcher.ps1'
$taskName = 'RGB Idle Watcher'

if (-not (Test-Path -LiteralPath $watcherScript)) {
    throw "Watcher script not found: $watcherScript"
}

# Keep Plex alive: display may turn off, but the PC must not sleep on AC power.
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0 | Out-Null
powercfg /setactive SCHEME_CURRENT | Out-Null

$taskInstalled = $false
try {
    $action = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $watcherScript)
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Turns supported RGB off when Windows reaches display idle timeout; does not put the PC to sleep.' -Force | Out-Null
    $taskInstalled = $true
} catch {
    $startupPath = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupPath 'RGB Idle Watcher.lnk'
    $vbsPath = Join-Path $startupPath 'RGB Idle Watcher.vbs'
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    $escapedScript = $watcherScript.Replace('"', '""')
    $escapedWorkDir = $scriptRoot.Replace('"', '""')
    $vbs = @"
Set shell = CreateObject("WScript.Shell")
shell.CurrentDirectory = "$escapedWorkDir"
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$escapedScript""", 0, False
"@
    Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ASCII
}

$existing = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object {
        $_.CommandLine -like "*-File*$watcherScript*" -or
        $_.CommandLine -like "*-File*rgb-idle-watcher.ps1*"
    }

if (-not $existing) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $watcherScript)
}

if ($taskInstalled) {
    Write-Host "Installed scheduled task and started: $taskName"
} else {
    Write-Host "Installed hidden Startup launcher and started: $taskName"
}
Write-Host "Log: $env:LOCALAPPDATA\RgbIdleWatcher\watcher.log"
