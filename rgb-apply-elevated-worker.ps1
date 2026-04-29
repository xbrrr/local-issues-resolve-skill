$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$stateArgPath = Join-Path $stateRoot 'pending-state.txt'
$msiRecoveryPath = Join-Path $stateRoot 'msi-recovery-request.txt'
$msiDirectV2RequestPath = Join-Path $stateRoot 'msi-direct-v2-request.txt'
$applyScript = Join-Path $scriptRoot 'rgb-apply-state.ps1'
$msiDirectScript = Join-Path $scriptRoot 'msi-mystic-direct.ps1'
$msiDirectV2Script = Join-Path $scriptRoot 'msi-mystic-direct-v2.ps1'
$logPath = Join-Path $stateRoot 'watcher.log'

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
}

function Invoke-MsiRecoveryIfRequested {
    if (-not (Test-Path -LiteralPath $msiRecoveryPath)) {
        return
    }

    $target = (Get-Content -LiteralPath $msiRecoveryPath -Raw).Trim()
    Remove-Item -LiteralPath $msiRecoveryPath -Force -ErrorAction SilentlyContinue
    if ($target -notin @('On', 'Off')) {
        Write-Log "MSI elevated recovery skipped: invalid target '$target'."
        return
    }

    Write-Log "MSI elevated recovery starting for $target."
    Get-Process DCv2,LEDKeeper2 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    foreach ($serviceName in @('Mystic_Light_Service', 'LightKeeperService')) {
        try {
            Restart-Service -Name $serviceName -Force -ErrorAction Stop
            Write-Log "MSI elevated recovery restarted service $serviceName."
        } catch {
            Write-Log "MSI elevated recovery service $serviceName restart failed: $($_.Exception.Message)"
        }
    }

    Start-Sleep -Seconds 5
    if (Test-Path -LiteralPath $msiDirectScript) {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $msiDirectScript -State $target 2>&1
        $joined = (($output | ForEach-Object { $_.ToString() }) -join ' | ')
        Write-Log "MSI elevated recovery direct apply target=$target exit=$LASTEXITCODE output=$joined"
    } else {
        Write-Log "MSI elevated recovery skipped direct apply: $msiDirectScript not found."
    }
}

function Invoke-MsiDirectV2IfRequested {
    if (-not (Test-Path -LiteralPath $msiDirectV2RequestPath)) {
        return $false
    }

    $target = (Get-Content -LiteralPath $msiDirectV2RequestPath -Raw).Trim()
    Remove-Item -LiteralPath $msiDirectV2RequestPath -Force -ErrorAction SilentlyContinue
    if ($target -notin @('On', 'Off', 'Discover')) {
        Write-Log "MSI direct v2 skipped: invalid target '$target'."
        return $true
    }

    if (-not (Test-Path -LiteralPath $msiDirectV2Script)) {
        Write-Log "MSI direct v2 skipped: script not found at $msiDirectV2Script."
        return $true
    }

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $msiDirectV2Script -State $target 2>&1
    $joined = (($output | ForEach-Object { $_.ToString() }) -join ' | ')
    Write-Log "MSI direct v2 elevated target=$target exit=$LASTEXITCODE output=$joined"
    return $true
}

function Invoke-MsiDirectV2State {
    param([ValidateSet('On', 'Off')][string]$TargetState)

    if (-not (Test-Path -LiteralPath $msiDirectV2Script)) {
        Write-Log "MSI direct v2 state skipped: script not found at $msiDirectV2Script."
        return
    }

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $msiDirectV2Script -State $TargetState 2>&1
    $joined = (($output | ForEach-Object { $_.ToString() }) -join ' | ')
    Write-Log "MSI direct v2 state target=$TargetState exit=$LASTEXITCODE output=$joined"
}

Invoke-MsiRecoveryIfRequested
if (Invoke-MsiDirectV2IfRequested) {
    exit 0
}

if (-not (Test-Path -LiteralPath $stateArgPath)) {
    Write-Log 'Elevated worker skipped: pending state file not found.'
    exit 0
}

$state = (Get-Content -LiteralPath $stateArgPath -Raw).Trim()
if ($state -notin @('On', 'Off')) {
    Write-Log "Elevated worker skipped: invalid state '$state'."
    exit 1
}

Write-Log "Elevated worker applying RGB state: $state"
Invoke-MsiDirectV2State -TargetState $state
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $applyScript -State $state -ElevatedWorker
