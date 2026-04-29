param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('On', 'Off')]
    [string]$State
)

$ErrorActionPreference = 'Stop'
$mysticDir = 'C:\Program Files (x86)\MSI\MSI Center\Mystic Light'
$dllPath = Join-Path $mysticDir 'MysticLight_AllDevice.dll'

if (-not [Environment]::Is64BitProcess) {
    [Environment]::CurrentDirectory = $mysticDir
    $assembly = [Reflection.Assembly]::LoadFrom($dllPath)
    $type = $assembly.GetType('MysticLight_AllDevice.Device.MB_800.MSI_800sLed', $true)
    $device = [Activator]::CreateInstance($type)

    $init = $type.GetMethod('Init')
    $setGlobal = $type.GetMethod('Set_GlobalSwitch')
    $applyBoard = $type.GetMethod('Gen1_ApplyBoard')
    $close = $type.GetMethod('CloseDevice')

    $initialized = [bool]$init.Invoke($device, @([UInt16]0))
    Write-Output "Init=$initialized"

    $enabled = $State -eq 'On'
    $setResult = [bool]$setGlobal.Invoke($device, @($enabled))
    Write-Output "Set_GlobalSwitch($enabled)=$setResult"

    $applyResult = [bool]$applyBoard.Invoke($device, @($true))
    Write-Output "Gen1_ApplyBoard(True)=$applyResult"

    [void]$close.Invoke($device, @())
    exit 0
}

$ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
& $ps32 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -State $State
