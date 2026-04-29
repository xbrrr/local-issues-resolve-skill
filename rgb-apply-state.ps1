param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('On', 'Off')]
    [string]$State,

    [switch]$Force,

    [switch]$ElevatedWorker
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$logPath = Join-Path $stateRoot 'watcher.log'
$winLightingBackupPath = Join-Path $stateRoot 'windows-lighting-backup.json'
$msiBackupPath = Join-Path $stateRoot 'msi-mystic-light-backup.json'
$msiPendingPath = Join-Path $stateRoot 'msi-mystic-pending-state.txt'
$msiResultPath = Join-Path $stateRoot 'msi-mystic-result.json'
$deepCoolScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'deepcool-lq094-state.ps1'
$powerIdleScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'power-idle-state.ps1'
$skydimoScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'skydimo-state.ps1'
$msiUiWorkerScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'msi-mystic-ui-worker.ps1'

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

if (-not $ElevatedWorker -and -not (Test-Path -LiteralPath (Join-Path $stateRoot 'disable-elevated-apply.flag'))) {
    $taskName = 'RGB Idle Apply Elevated'
    $stateArgPath = Join-Path $stateRoot 'pending-state.txt'
    Set-Content -LiteralPath $stateArgPath -Value $State -Encoding ASCII
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            if (Test-Path -LiteralPath $msiUiWorkerScript) {
                Remove-Item -LiteralPath $msiResultPath -Force -ErrorAction SilentlyContinue
                Set-Content -LiteralPath $msiPendingPath -Value $State -Encoding ASCII
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $msiUiWorkerScript | Out-Null
                if (Test-Path -LiteralPath $msiResultPath) {
                    $result = Get-Content -LiteralPath $msiResultPath -Raw | ConvertFrom-Json
                    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') MSI Mystic Light user-session result: ok=$($result.ok) message=$($result.message)" -Encoding UTF8
                } else {
                    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') MSI Mystic Light user-session result missing." -Encoding UTF8
                }
            }
            if (Test-Path -LiteralPath $skydimoScript) {
                try {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $skydimoScript -State $State | Out-Null
                } catch {
                    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Skydimo user-session state skipped: $($_.Exception.Message)" -Encoding UTF8
                }
            }
            Start-ScheduledTask -TaskName $taskName
            Start-Sleep -Seconds 2
            return
        }
    } catch {
        # Fall through to the non-elevated path if the task is not installed yet.
    }
}

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Export-RegistryValues {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $item = Get-ItemProperty -LiteralPath $Path
    $values = @{}
    foreach ($property in $item.PSObject.Properties) {
        if ($property.Name -notmatch '^PS') {
            $values[$property.Name] = $property.Value
        }
    }
    return $values
}

function Set-WindowsDynamicLighting {
    param([string]$TargetState)

    $base = 'HKCU:\Software\Microsoft\Lighting'
    if (-not (Test-Path -LiteralPath $base)) {
        Write-Log 'Windows Dynamic Lighting registry key not found; skipped.'
        return
    }

    if ($TargetState -eq 'Off') {
        if (-not (Test-Path -LiteralPath $winLightingBackupPath)) {
            $backup = @{
                Base = Export-RegistryValues -Path $base
                Devices = @{}
            }
            $devicesRoot = Join-Path $base 'Devices'
            if (Test-Path -LiteralPath $devicesRoot) {
                foreach ($device in Get-ChildItem -LiteralPath $devicesRoot -ErrorAction SilentlyContinue) {
                    $backup.Devices[$device.PSChildName] = Export-RegistryValues -Path $device.PSPath
                }
            }
            $backup | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $winLightingBackupPath -Encoding UTF8
        }

        New-Item -Path $base -Force | Out-Null
        New-ItemProperty -Path $base -Name AmbientLightingEnabled -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $base -Name Brightness -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $base -Name Color -PropertyType DWord -Value 0 -Force | Out-Null

        $devicesRoot = Join-Path $base 'Devices'
        if (Test-Path -LiteralPath $devicesRoot) {
            foreach ($device in Get-ChildItem -LiteralPath $devicesRoot -ErrorAction SilentlyContinue) {
                New-ItemProperty -Path $device.PSPath -Name Brightness -PropertyType DWord -Value 0 -Force | Out-Null
                New-ItemProperty -Path $device.PSPath -Name Color -PropertyType DWord -Value 0 -Force | Out-Null
            }
        }
        Write-Log 'Windows Dynamic Lighting set to off.'
        return
    }

    if ($TargetState -eq 'On' -and (Test-Path -LiteralPath $winLightingBackupPath)) {
        $backup = Get-Content -LiteralPath $winLightingBackupPath -Raw | ConvertFrom-Json
        if ($backup.Base) {
            foreach ($property in $backup.Base.PSObject.Properties) {
                New-ItemProperty -Path $base -Name $property.Name -Value $property.Value -Force | Out-Null
            }
        }

        $devicesRoot = Join-Path $base 'Devices'
        if ($backup.Devices -and (Test-Path -LiteralPath $devicesRoot)) {
            foreach ($deviceName in $backup.Devices.PSObject.Properties.Name) {
                $devicePath = Join-Path $devicesRoot $deviceName
                if (Test-Path -LiteralPath $devicePath) {
                    foreach ($property in $backup.Devices.$deviceName.PSObject.Properties) {
                        New-ItemProperty -Path $devicePath -Name $property.Name -Value $property.Value -Force | Out-Null
                    }
                }
            }
        }
        Write-Log 'Windows Dynamic Lighting restored from backup.'
    }
}

function Set-MsiMysticLight {
    param([string]$TargetState)

    $path = 'HKLM:\SOFTWARE\WOW6432Node\MSI\MSI Center\Component\Mystic Light\LED'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Log 'MSI Mystic Light registry key not found; skipped.'
        return
    }

    if (-not (Test-IsAdmin)) {
        Write-Log 'MSI Mystic Light skipped: administrator rights are required for HKLM writes.'
        return
    }

    if ($TargetState -eq 'Off') {
        if (-not (Test-Path -LiteralPath $msiBackupPath)) {
            $backup = Export-RegistryValues -Path $path
            $backup | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $msiBackupPath -Encoding UTF8
        }

        if (Invoke-MsiMysticLightUiTask -TargetState $TargetState) {
            Write-Log 'MSI Mystic Light switched off through MSI Center UI.'
        } else {
            Write-Log 'MSI Mystic Light off failed: MSI Center UI switch was not applied.'
        }
        return
    }

    if ($TargetState -eq 'On' -and (Test-Path -LiteralPath $msiBackupPath)) {
        $backup = Get-Content -LiteralPath $msiBackupPath -Raw | ConvertFrom-Json

        foreach ($property in $backup.PSObject.Properties) {
            if ($property.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) {
                Set-ItemProperty -LiteralPath $path -Name $property.Name -Value $property.Value -ErrorAction SilentlyContinue
            }
        }

        if (Invoke-MsiMysticLightUiTask -TargetState $TargetState) {
            Write-Log 'MSI Mystic Light restored through MSI Center UI.'
        } else {
            Write-Log 'MSI Mystic Light restore failed: MSI Center UI switch was not applied.'
        }
    }
}

function Invoke-MsiMysticLightUiTask {
    param([string]$TargetState)

    try {
        $taskName = 'RGB MSI Mystic UI'
        Remove-Item -LiteralPath $msiResultPath -Force -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $msiPendingPath -Value $TargetState -Encoding ASCII

        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Log "MSI Mystic Light UI task '$taskName' not found."
            return $false
        }

        Start-ScheduledTask -TaskName $taskName
        $deadline = (Get-Date).AddSeconds(75)
        do {
            if (Test-Path -LiteralPath $msiResultPath) {
                $result = Get-Content -LiteralPath $msiResultPath -Raw | ConvertFrom-Json
                Write-Log "MSI Mystic Light UI task result: ok=$($result.ok) message=$($result.message)"
                return [bool]$result.ok
            }
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)

        Write-Log 'MSI Mystic Light UI task timed out.'
        return $false
    } catch {
        Write-Log "MSI Mystic Light UI task failed: $($_.Exception.Message)"
        return $false
    }
}

function Set-DeepCoolLq094 {
    param([string]$TargetState)

    if (-not (Test-Path -LiteralPath $deepCoolScript)) {
        Write-Log 'DeepCool LQ094 script not found; skipped.'
        return
    }

    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deepCoolScript -State $TargetState | Out-Null
    } catch {
        Write-Log "DeepCool LQ094 skipped: $($_.Exception.Message)"
    }
}

function Set-PowerIdleState {
    param([string]$TargetState)

    if (-not (Test-Path -LiteralPath $powerIdleScript)) {
        Write-Log 'Power idle script not found; skipped.'
        return
    }

    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $powerIdleScript -State $TargetState | Out-Null
    } catch {
        Write-Log "Power idle state skipped: $($_.Exception.Message)"
    }
}

function Set-SkydimoState {
    param([string]$TargetState)

    if (-not (Test-Path -LiteralPath $skydimoScript)) {
        Write-Log 'Skydimo script not found; skipped.'
        return
    }

    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $skydimoScript -State $TargetState | Out-Null
    } catch {
        Write-Log "Skydimo state skipped: $($_.Exception.Message)"
    }
}

Write-Log "Applying RGB state: $State"
Set-PowerIdleState -TargetState $State
Set-WindowsDynamicLighting -TargetState $State
if (-not $ElevatedWorker) {
    Set-MsiMysticLight -TargetState $State
} else {
    Write-Log 'MSI Mystic Light skipped in elevated worker; user-session worker owns MSI Center UI.'
}
Set-DeepCoolLq094 -TargetState $State
if (-not $ElevatedWorker) {
    Set-SkydimoState -TargetState $State
} else {
    Write-Log 'Skydimo skipped in elevated worker; user-session worker owns hotkey control.'
}
