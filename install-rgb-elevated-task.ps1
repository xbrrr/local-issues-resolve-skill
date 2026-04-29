$ErrorActionPreference = 'Stop'

$taskName = 'RGB Idle Apply Elevated'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$worker = Join-Path $scriptRoot 'rgb-apply-elevated-worker.ps1'
$logPath = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher\install-elevated-task.log'

New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force | Out-Null

try {
    if (-not (Test-Path -LiteralPath $worker)) {
        throw "Worker script not found: $worker"
    }

    $argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $worker
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -Hidden `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null

    Set-Content -LiteralPath $logPath -Value "$(Get-Date -Format s) OK: installed task '$taskName' for user '$env:USERNAME'." -Encoding UTF8
    Write-Host "OK: installed task '$taskName'."
} catch {
    Set-Content -LiteralPath $logPath -Value "$(Get-Date -Format s) ERROR: $($_.Exception.Message)" -Encoding UTF8
    Write-Error $_
    exit 1
}
