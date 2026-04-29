param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('On', 'Off', 'Status')]
    [string]$State
)

$ErrorActionPreference = 'Stop'
$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$logPath = Join-Path $stateRoot 'watcher.log'
$controllerPath = Join-Path $env:LOCALAPPDATA 'SkyDimo\controllers\SK0127_3C12222B113C29.json'
$skydimoExe = 'C:\Program Files\SkyDimo\SkyDimo.exe'

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $controllerPath)) {
    throw "SkyDimo controller config not found: $controllerPath"
}

$config = Get-Content -LiteralPath $controllerPath -Raw | ConvertFrom-Json
if ($State -eq 'Status') {
    [pscustomobject]@{
        Path = $controllerPath
        Enable = [bool]$config.enable
        Brightness = $config.brightness
        WorkMode = $config.workMode
        SubMode = $config.subMode
    } | Format-List
    exit 0
}

$desired = ($State -eq 'On')
if ([bool]$config.enable -eq $desired) {
    Write-Output "SkyDimo already $State in config."
    Write-Log "SkyDimo config direct already $State."
    exit 0
}

$backupPath = Join-Path $stateRoot "skydimo-controller-direct-before-$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
Copy-Item -LiteralPath $controllerPath -Destination $backupPath -Force
$config.enable = $desired
$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $controllerPath -Encoding UTF8

Get-Process SkyDimo -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
if (Test-Path -LiteralPath $skydimoExe) {
    Start-Process -FilePath $skydimoExe -ArgumentList '--auto_startup' -WindowStyle Hidden
}
Write-Output "SkyDimo config set to $State. Backup=$backupPath"
Write-Log "SkyDimo config direct set to $State using $backupPath."
