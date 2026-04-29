param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('On', 'Off')]
    [string]$State
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$logPath = Join-Path $stateRoot 'watcher.log'
$activeBackupPath = Join-Path $stateRoot 'active-power-scheme.txt'
$idleSchemeName = 'Plex Idle'
$idleSchemeGuid = '69356ebb-9c01-427c-8625-f1c21ff6f2c0'
$defaultGameSchemeGuid = 'd6dc1319-c076-4fcc-b8be-a7187a370390'

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
}

function Get-ActivePowerSchemeGuid {
    $line = powercfg /getactivescheme
    if ($line -match '([0-9a-fA-F-]{36})') {
        return $matches[1]
    }
    throw 'Could not read active power scheme.'
}

function Test-PowerSchemeExists {
    param([string]$Guid)
    $schemes = powercfg /list
    return [bool]($schemes -match [regex]::Escape($Guid))
}

function Ensure-IdleScheme {
    if (Test-PowerSchemeExists -Guid $idleSchemeGuid) {
        return
    }

    $duplicate = powercfg /duplicatescheme SCHEME_BALANCED $idleSchemeGuid
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create $idleSchemeName scheme: $duplicate"
    }

    powercfg /changename $idleSchemeGuid $idleSchemeName 'Low-power idle plan for Plex server: no sleep, reduced idle power.' | Out-Null
    powercfg /setacvalueindex $idleSchemeGuid SUB_SLEEP STANDBYIDLE 0 | Out-Null
    powercfg /setacvalueindex $idleSchemeGuid SUB_SLEEP HIBERNATEIDLE 0 | Out-Null
    powercfg /setacvalueindex $idleSchemeGuid SUB_VIDEO VIDEOIDLE 900 | Out-Null
    powercfg /setacvalueindex $idleSchemeGuid SUB_PROCESSOR PROCTHROTTLEMIN 5 | Out-Null
    powercfg /setacvalueindex $idleSchemeGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 | Out-Null
    powercfg /setacvalueindex $idleSchemeGuid SUB_PCIEXPRESS ASPM 2 | Out-Null
    powercfg /setacvalueindex $idleSchemeGuid SUB_DISK DISKIDLE 0 | Out-Null
}

Ensure-IdleScheme

if ($State -eq 'Off') {
    $active = Get-ActivePowerSchemeGuid
    if ($active -ne $idleSchemeGuid) {
        Set-Content -LiteralPath $activeBackupPath -Value $active -Encoding ASCII
    }
    powercfg /setactive $idleSchemeGuid | Out-Null
    Write-Log "Power scheme set to $idleSchemeName ($idleSchemeGuid). Previous=$active"
    return
}

$restoreGuid = $defaultGameSchemeGuid
if (Test-Path -LiteralPath $activeBackupPath) {
    $candidate = (Get-Content -LiteralPath $activeBackupPath -Raw).Trim()
    if ($candidate -match '^[0-9a-fA-F-]{36}$' -and (Test-PowerSchemeExists -Guid $candidate)) {
        $restoreGuid = $candidate
    }
}

powercfg /setactive $restoreGuid | Out-Null
Write-Log "Power scheme restored to $restoreGuid."
