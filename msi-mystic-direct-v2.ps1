param(
    [ValidateSet('Discover', 'On', 'Off')]
    [string]$State = 'Discover',

    [byte]$Red = 255,
    [byte]$Green = 255,
    [byte]$Blue = 255
)

$ErrorActionPreference = 'Stop'
$mysticDir = 'C:\Program Files (x86)\MSI\MSI Center\Mystic Light'
$dllPath = Join-Path $mysticDir 'MysticLight_AllDevice.dll'
$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$logPath = Join-Path $stateRoot 'watcher.log'

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $dllPath)) {
    throw "MysticLight_AllDevice.dll not found: $dllPath"
}

if ([Environment]::Is64BitProcess) {
    $ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    & $ps32 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -State $State -Red $Red -Green $Green -Blue $Blue
    exit $LASTEXITCODE
}

[Environment]::CurrentDirectory = $mysticDir
$assembly = [Reflection.Assembly]::LoadFrom($dllPath)

function New-TypeInstance {
    param([string]$TypeName)
    $type = $assembly.GetType($TypeName, $true)
    return [Activator]::CreateInstance($type)
}

function Invoke-AllDeviceDiscover {
    $device = New-TypeInstance -TypeName 'MysticLight_AllDevice.Device.AllDevice'
    $type = $device.GetType()
    $type.GetMethod('Init_AllDevice').Invoke($device, @())
    Start-Sleep -Seconds 2

    $summary = [ordered]@{}
    foreach ($member in $type.GetMembers([Reflection.BindingFlags]'Public,NonPublic,Instance')) {
        if ($member.MemberType -eq 'Field') {
            try {
                $value = $member.GetValue($device)
                if ($null -ne $value -and $member.Name -match 'Device|MB|LED|Support|Count|Num|Model|Name') {
                    $summary[$member.Name] = $value.ToString()
                }
            } catch {}
        } elseif ($member.MemberType -eq 'Property') {
            try {
                if ($member.GetIndexParameters().Count -eq 0 -and $member.Name -match 'Device|MB|LED|Support|Count|Num|Model|Name') {
                    $value = $member.GetValue($device, $null)
                    if ($null -ne $value) {
                        $summary[$member.Name] = $value.ToString()
                    }
                }
            } catch {}
        }
    }

    try {
        $type.GetMethod('Close_AllDevice_MB').Invoke($device, @())
    } catch {}
    try {
        $type.GetMethod('Close_AllDevice_USB').Invoke($device, @())
    } catch {}

    return $summary
}

function Invoke-AllDeviceApply {
    param([ValidateSet('On', 'Off')][string]$TargetState)

    $device = New-TypeInstance -TypeName 'MysticLight_AllDevice.Device.AllDevice'
    $type = $device.GetType()
    $type.GetMethod('Init_AllDevice').Invoke($device, @())
    Start-Sleep -Seconds 2

    if ($TargetState -eq 'Off') {
        $type.GetMethod('Set_Style_Off').Invoke($device, @())
        Write-Output 'AllDevice.Set_Style_Off invoked'
        Write-Log 'MSI Mystic direct v2 invoked AllDevice.Set_Style_Off.'
    } else {
        $type.GetMethod('Set_LED_Static').Invoke($device, @([int]0, $Red, $Green, $Blue))
        Write-Output "AllDevice.Set_LED_Static invoked index=0 rgb=$Red,$Green,$Blue"
        Write-Log "MSI Mystic direct v2 invoked AllDevice.Set_LED_Static index=0 rgb=$Red,$Green,$Blue."
    }

    Start-Sleep -Seconds 1
    try {
        $type.GetMethod('Close_AllDevice_MB').Invoke($device, @())
    } catch {}
    try {
        $type.GetMethod('Close_AllDevice_USB').Invoke($device, @())
    } catch {}
}

if ($State -eq 'Discover') {
    $result = Invoke-AllDeviceDiscover
    $result.GetEnumerator() | Sort-Object Name | ForEach-Object {
        '{0}={1}' -f $_.Name, $_.Value
    }
    Write-Log "MSI Mystic direct v2 discover completed with $($result.Count) values."
    exit 0
}

Invoke-AllDeviceApply -TargetState $State
