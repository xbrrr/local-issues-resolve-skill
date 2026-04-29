$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$applyScript = Join-Path $scriptRoot 'rgb-apply-state.ps1'
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

Write-Log 'RGB Idle Watcher started.'
$displayIdleSeconds = Get-DisplayIdleSeconds
if ($displayIdleSeconds -le 0) {
    $displayIdleSeconds = 900
}
$idleSeconds = [math]::Floor([IdleTime]::GetIdleMilliseconds() / 1000)
$lastState = if ($idleSeconds -ge $displayIdleSeconds) { 'Off' } else { 'On' }
Write-Log "Startup sync: IdleSeconds=$idleSeconds DisplayTimeout=$displayIdleSeconds TargetState=$lastState"
Apply-State -State $lastState -Force

# Some vendor tools are controlled through simulated hotkeys. Those hotkeys reset
# Windows' idle timer and previously caused an immediate Off -> On flip after the
# monitors powered down. While latched off, only a very fresh input sample should
# wake RGB back up.
$wakeIdleSeconds = 3
$ignoreSyntheticWakeUntil = [DateTime]::MinValue

while ($true) {
    try {
        $displayIdleSeconds = Get-DisplayIdleSeconds
        if ($displayIdleSeconds -le 0) {
            $displayIdleSeconds = 900
        }

        $idleSeconds = [math]::Floor([IdleTime]::GetIdleMilliseconds() / 1000)
        if ($lastState -eq 'Off') {
            if ((Get-Date) -lt $ignoreSyntheticWakeUntil) {
                $targetState = 'Off'
            } else {
                $targetState = if ($idleSeconds -le $wakeIdleSeconds) { 'On' } else { 'Off' }
            }
        } else {
            $targetState = if ($idleSeconds -ge $displayIdleSeconds) { 'Off' } else { 'On' }
        }

        if ($targetState -ne $lastState) {
            Write-Log "IdleSeconds=$idleSeconds DisplayTimeout=$displayIdleSeconds TargetState=$targetState"
            Apply-State -State $targetState
            $lastState = $targetState
            if ($targetState -eq 'Off') {
                $ignoreSyntheticWakeUntil = (Get-Date).AddSeconds(30)
            }
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
