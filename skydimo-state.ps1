param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('On', 'Off')]
    [string]$State,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$logPath = Join-Path $stateRoot 'watcher.log'
$statePath = Join-Path $stateRoot 'skydimo-state.txt'
$skydimoExe = 'C:\Program Files (x86)\Skydimo\SkyDimo.exe'
$controllerPath = Join-Path $env:LOCALAPPDATA 'SkyDimo\controllers\SK0127_3C12222B113C29.json'

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
}

function Ensure-SkydimoRunning {
    $process = Get-Process SkyDimo -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($process) {
        return
    }

    if (-not (Test-Path -LiteralPath $skydimoExe)) {
        throw "Skydimo executable not found: $skydimoExe"
    }

    Start-Process -FilePath $skydimoExe -ArgumentList '--auto_startup' -WindowStyle Hidden
    Start-Sleep -Seconds 5
}

function Test-Ch340Present {
    $device = Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -like '*CH340*' -and $_.Status -eq 'OK' } |
        Select-Object -First 1
    return ($null -ne $device)
}

function Get-LatestSkydimoLogPath {
    $logRoot = Join-Path $env:LOCALAPPDATA 'SkyDimo\logs'
    if (-not (Test-Path -LiteralPath $logRoot)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $logRoot -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Test-SkydimoControllerDisconnected {
    $latestLog = Get-LatestSkydimoLogPath
    if (-not $latestLog) {
        return $false
    }

    $lines = Get-Content -LiteralPath $latestLog -Tail 250 -ErrorAction SilentlyContinue
    $lastConnect = -1
    $lastDisconnect = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match 'SK0127:3C12222B113C29' -and $line -match 'has connected') {
            $lastConnect = $i
        }
        if ($line -match 'SK0127:3C12222B113C29' -and ($line -match 'has disconected|Device has failed|Starts removing controller')) {
            $lastDisconnect = $i
        }
    }

    return ($lastDisconnect -ge 0 -and $lastDisconnect -gt $lastConnect)
}

function Restart-Skydimo {
    if (-not (Test-Path -LiteralPath $skydimoExe)) {
        throw "Skydimo executable not found: $skydimoExe"
    }

    Get-Process SkyDimo -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 3
    Start-Process -FilePath $skydimoExe -ArgumentList '--auto_startup' -WindowStyle Hidden
    Start-Sleep -Seconds 8
}

function Set-SkydimoConfigState {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('On', 'Off')]
        [string]$DesiredState
    )

    if (-not (Test-Path -LiteralPath $controllerPath)) {
        throw "Skydimo controller config not found: $controllerPath"
    }

    if (-not (Test-Path -LiteralPath $skydimoExe)) {
        throw "Skydimo executable not found: $skydimoExe"
    }

    $backupPath = Join-Path $stateRoot "skydimo-controller-before-fallback-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    Copy-Item -LiteralPath $controllerPath -Destination $backupPath -Force

    Get-Process SkyDimo -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2

    $config = Get-Content -LiteralPath $controllerPath -Raw | ConvertFrom-Json
    $config.enable = ($DesiredState -eq 'On')
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $controllerPath -Encoding UTF8

    Start-Process -FilePath $skydimoExe -ArgumentList '--auto_startup' -WindowStyle Hidden
    Start-Sleep -Seconds 8

    Write-Log "Skydimo config fallback applied $DesiredState using $backupPath."
    return (Get-SkydimoActualState)
}

function Repair-SkydimoConnectionIfNeeded {
    if ((Test-Ch340Present) -and (Test-SkydimoControllerDisconnected)) {
        Write-Log 'Skydimo controller disconnected while CH340 is present; restarting SkyDimo.'
        Restart-Skydimo
    }
}

function Send-SkydimoToggleHotkey {
    # SkyDimo stores turnOffOn as Qt Key_F10 with Ctrl+Alt+Shift modifiers.
    $shell = New-Object -ComObject WScript.Shell
    $shell.SendKeys('^%+{F10}')
}

function Get-SkydimoActualState {
    if (Test-Path -LiteralPath $controllerPath) {
        try {
            $config = Get-Content -LiteralPath $controllerPath -Raw | ConvertFrom-Json
            if ($null -ne $config.enable) {
                if ([bool]$config.enable) {
                    return 'On'
                }
                return 'Off'
            }
        } catch {
            Write-Log "Skydimo actual state read failed: $($_.Exception.Message)"
        }
    }

    if (Test-Path -LiteralPath $statePath) {
        $tracked = (Get-Content -LiteralPath $statePath -Raw).Trim()
        if ($tracked -in @('On', 'Off')) {
            return $tracked
        }
    }

    return $null
}

function Wait-SkydimoState {
    param([string]$ExpectedState)

    $deadline = (Get-Date).AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 500
        $actual = Get-SkydimoActualState
        if ($actual -eq $ExpectedState) {
            return $actual
        }
    } while ((Get-Date) -lt $deadline)

    return (Get-SkydimoActualState)
}

Ensure-SkydimoRunning
Repair-SkydimoConnectionIfNeeded

$actualState = Get-SkydimoActualState

if ($actualState -eq $State) {
    Set-Content -LiteralPath $statePath -Value $actualState -Encoding ASCII
    Write-Log "Skydimo already actual $State; skipped."
    return
}

Send-SkydimoToggleHotkey
$afterState = Wait-SkydimoState -ExpectedState $State

if ($afterState -ne $State -and (Test-Ch340Present)) {
    Write-Log "Skydimo requested $State but actual state is $afterState; restarting SkyDimo and retrying once."
    Restart-Skydimo
    $actualState = Get-SkydimoActualState
    if ($actualState -ne $State) {
        Send-SkydimoToggleHotkey
        $afterState = Wait-SkydimoState -ExpectedState $State
    } else {
        $afterState = $actualState
    }
}

if ($afterState -ne $State -and (Test-Ch340Present)) {
    Write-Log "Skydimo hotkey retry did not reach $State; applying config fallback."
    $afterState = Set-SkydimoConfigState -DesiredState $State
}

if ($afterState -in @('On', 'Off')) {
    Set-Content -LiteralPath $statePath -Value $afterState -Encoding ASCII
} else {
    Set-Content -LiteralPath $statePath -Value $State -Encoding ASCII
}

if ($afterState -eq $State) {
    Write-Log "Skydimo toggled to actual state $State."
} else {
    Write-Log "Skydimo requested $State but actual state is $afterState."
}
