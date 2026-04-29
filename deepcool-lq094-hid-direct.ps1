param(
    [ValidateSet('List', 'Blank')]
    [string]$Action = 'List'
)

$ErrorActionPreference = 'Stop'
$vendorId = 0x3633
$productId = 0x000d
$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$logPath = Join-Path $stateRoot 'watcher.log'

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
}

function Add-HidApi {
    $source = @'
using System;
using System.Runtime.InteropServices;

public static class HidApiNative {
    [DllImport("hidapi.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern int hid_init();

    [DllImport("hidapi.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr hid_open(ushort vendor_id, ushort product_id, IntPtr serial_number);

    [DllImport("hidapi.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern int hid_write(IntPtr device, byte[] data, UIntPtr length);

    [DllImport("hidapi.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern void hid_close(IntPtr device);
}
'@
    Add-Type -TypeDefinition $source -ErrorAction SilentlyContinue
}

function Get-DeepCoolUsbDevices {
    Get-CimInstance Win32_PnPEntity |
        Where-Object { $_.PNPDeviceID -match 'VID_3633&PID_000D' } |
        Select-Object Name, PNPClass, Manufacturer, PNPDeviceID, Status
}

if ($Action -eq 'List') {
    Get-DeepCoolUsbDevices | Format-List
    Write-Log 'DeepCool LQ094 HID direct list completed.'
    exit 0
}

$openRgbDir = 'C:\Program Files\OpenRGB'
$env:PATH = "$openRgbDir;$env:PATH"
Add-HidApi
[void][HidApiNative]::hid_init()
$device = [HidApiNative]::hid_open([uint16]$vendorId, [uint16]$productId, [IntPtr]::Zero)
if ($device -eq [IntPtr]::Zero) {
    throw 'Could not open DeepCool LQ094 HID device. Close DeepCool.exe or run elevated if the device is busy.'
}

try {
    # LQ-series packet shape from deepcool-digital-linux:
    # report=0x10 command=0x68 kind=1 length=8 flags=12,1,2, payload, checksum, terminator=0x16.
    # This blanks all displayed numeric values. Backlight power is not guaranteed by this packet.
    $packet = New-Object byte[] 64
    $packet[0] = 0x10
    $packet[1] = 0x68
    $packet[2] = 0x01
    $packet[3] = 0x08
    $packet[4] = 0x0c
    $packet[5] = 0x01
    $packet[6] = 0x02
    $sum = 0
    for ($i = 1; $i -le 16; $i++) {
        $sum += $packet[$i]
    }
    $packet[17] = [byte]($sum % 256)
    $packet[18] = 0x16
    $length = [UIntPtr]::new([uint32]64)
    $written = [HidApiNative]::hid_write($device, $packet, $length)
    Write-Output "DeepCool HID blank packet written bytes=$written"
    Write-Log "DeepCool LQ094 HID blank packet written bytes=$written."
} finally {
    [HidApiNative]::hid_close($device)
}
