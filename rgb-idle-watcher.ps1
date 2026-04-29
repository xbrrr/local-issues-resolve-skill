$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$applyScript = Join-Path $scriptRoot 'rgb-apply-state.ps1'
$deepCoolScript = Join-Path $scriptRoot 'deepcool-lq094-state.ps1'
$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$logPath = Join-Path $stateRoot 'watcher.log'
$statusPath = Join-Path $stateRoot 'state.txt'
$mutex = [Threading.Mutex]::new($false, 'Local\RgbIdleWatcher')

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

if (-not $mutex.WaitOne(0)) {
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Watcher already running; exiting." -Encoding UTF8
    exit 0
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class IdleTime {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref lii);
        return ((uint)Environment.TickCount - lii.dwTime);
    }

    [DllImport("user32.dll", SetLastError=true)]
    private static extern IntPtr OpenInputDesktop(uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll", SetLastError=true)]
    private static extern bool CloseDesktop(IntPtr hDesktop);

    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern bool GetUserObjectInformation(IntPtr hObj, int nIndex, StringBuilder pvInfo, int nLength, ref int lpnLengthNeeded);

    public static string GetInputDesktopName() {
        IntPtr desktop = OpenInputDesktop(0, false, 1);
        if (desktop == IntPtr.Zero) {
            return "";
        }

        try {
            int needed = 0;
            StringBuilder name = new StringBuilder(256);
            if (GetUserObjectInformation(desktop, 2, name, name.Capacity, ref needed)) {
                return name.ToString();
            }
            return "";
        } finally {
            CloseDesktop(desktop);
        }
    }
}
'@

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
}

function Get-DisplayIdleSeconds {
    $output = powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 2>$null
    $hexValues = @()
    foreach ($line in $output) {
        if ($line -match '0x([0-9a-fA-F]{8})') {
            $hexValues += $matches[1]
        }
    }
    if ($hexValues.Count -ge 2) {
        return [Convert]::ToInt32($hexValues[$hexValues.Count - 2], 16)
    }
    return 900
}

function Apply-State {
    param(
        [ValidateSet('On', 'Off')][string]$State,
        [switch]$Force
    )
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $applyScript, '-State', $State)
    if ($Force) {
        $arguments += '-Force'
    }
    & powershell.exe @arguments | Out-Null
    Set-Content -LiteralPath $statusPath -Value $State -Encoding ASCII
}

function Test-SessionLocked {
    $desktopName = [IdleTime]::GetInputDesktopName()
    return ($desktopName -and $desktopName -ne 'Default')
}

Write-Log 'RGB Idle Watcher started.'
$displayIdleSeconds = Get-DisplayIdleSeconds
if ($displayIdleSeconds -le 0) {
    $displayIdleSeconds = 900
}
$idleSeconds = [math]::Floor([IdleTime]::GetIdleMilliseconds() / 1000)
$sessionLocked = Test-SessionLocked
$lastSessionLocked = $sessionLocked
$lastState = if ($sessionLocked -or $idleSeconds -ge $displayIdleSeconds) { 'Off' } else { 'On' }
Write-Log "Startup sync: IdleSeconds=$idleSeconds DisplayTimeout=$displayIdleSeconds SessionLocked=$sessionLocked TargetState=$lastState"
Apply-State -State $lastState -Force

# Some vendor tools are controlled through simulated hotkeys. Those hotkeys reset
# Windows' idle timer and previously caused an immediate Off -> On flip after the
# monitors powered down. While latched off, only a very fresh input sample should
# wake RGB back up.
$wakeIdleSeconds = 3
$ignoreSyntheticWakeUntil = [DateTime]::MinValue
$lastDeepCoolOffGuard = [DateTime]::MinValue
$lastHeartbeat = [DateTime]::MinValue

function Invoke-DeepCoolOffGuard {
    param(
        [int]$IdleSeconds,
        [int]$DisplayIdleSeconds
    )

    if (-not (Test-Path -LiteralPath $deepCoolScript)) {
        return $false
    }

    $deepCoolProcess = Get-Process DeepCool -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $deepCoolProcess) {
        return $false
    }

    $now = Get-Date
    if (($now - $lastDeepCoolOffGuard).TotalSeconds -lt 120) {
        return $false
    }

    Write-Log "DeepCool idle-off guard: IdleSeconds=$IdleSeconds DisplayTimeout=$DisplayIdleSeconds process=$($deepCoolProcess.Id)."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deepCoolScript -State Off | Out-Null
    Set-Content -LiteralPath $statusPath -Value 'Off' -Encoding ASCII
    $script:lastDeepCoolOffGuard = $now
    return $true
}

while ($true) {
    try {
        $displayIdleSeconds = Get-DisplayIdleSeconds
        if ($displayIdleSeconds -le 0) {
            $displayIdleSeconds = 900
        }

        $idleSeconds = [math]::Floor([IdleTime]::GetIdleMilliseconds() / 1000)
        $sessionLocked = Test-SessionLocked
        if ($sessionLocked -ne $lastSessionLocked) {
            Write-Log "Session lock state changed: Locked=$sessionLocked"
            $lastSessionLocked = $sessionLocked
        }

        if ($lastState -eq 'Off') {
            if ((Get-Date) -lt $ignoreSyntheticWakeUntil) {
                $targetState = 'Off'
            } else {
                $targetState = if ((-not $sessionLocked) -and $idleSeconds -le $wakeIdleSeconds) { 'On' } else { 'Off' }
            }
        } else {
            $targetState = if ($sessionLocked -or $idleSeconds -ge $displayIdleSeconds) { 'Off' } else { 'On' }
        }

        if ($targetState -ne $lastState) {
            Write-Log "IdleSeconds=$idleSeconds DisplayTimeout=$displayIdleSeconds SessionLocked=$sessionLocked TargetState=$targetState"
            Apply-State -State $targetState
            $lastState = $targetState
            if ($targetState -eq 'Off') {
                $ignoreSyntheticWakeUntil = (Get-Date).AddSeconds(30)
            }
        }

        if ($sessionLocked -or $idleSeconds -ge $displayIdleSeconds) {
            if (Invoke-DeepCoolOffGuard -IdleSeconds $idleSeconds -DisplayIdleSeconds $displayIdleSeconds) {
                $lastState = 'Off'
                $ignoreSyntheticWakeUntil = (Get-Date).AddSeconds(30)
            }
        }

        if (((Get-Date) - $lastHeartbeat).TotalMinutes -ge 5) {
            Write-Log "Watcher heartbeat: IdleSeconds=$idleSeconds DisplayTimeout=$displayIdleSeconds SessionLocked=$sessionLocked LastState=$lastState"
            $lastHeartbeat = Get-Date
        }
    } catch {
        Write-Log "Watcher error: $($_.Exception.Message)"
    }

    if ($lastState -eq 'Off') {
        Start-Sleep -Seconds 1
    } else {
        Start-Sleep -Seconds 10
    }
}
