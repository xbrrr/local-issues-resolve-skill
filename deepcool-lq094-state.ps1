param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('On', 'Off')]
    [string]$State
)

$ErrorActionPreference = 'Stop'
$serialNumber = '1039935A05A7'
$debugPort = 9223
$deepCoolExe = 'C:\DeepCool\DeepCool.exe'
$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$logPath = Join-Path $stateRoot 'watcher.log'
$backupPath = Join-Path $stateRoot 'deepcool-lq094-backup.json'

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
}

function Get-DeepCoolPage {
    try {
        $pages = Invoke-RestMethod -Uri "http://127.0.0.1:$debugPort/json" -TimeoutSec 2
        return ($pages | Where-Object { $_.url -like '*index.html*' } | Select-Object -First 1)
    } catch {
        return $null
    }
}

function Hide-DeepCoolWindows {
    $source = @'
using System;
using System.Runtime.InteropServices;

public static class DeepCoolWindowTools {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
    Add-Type -TypeDefinition $source -ErrorAction SilentlyContinue

    Get-Process DeepCool -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
        ForEach-Object {
            [void][DeepCoolWindowTools]::ShowWindow($_.MainWindowHandle, 0)
        }
}

function Hide-DeepCoolWindowsFor {
    param([int]$Seconds = 8)

    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        Hide-DeepCoolWindows
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
}


function Start-DeepCoolWithDebugPort {
    if (-not (Test-Path -LiteralPath $deepCoolExe)) {
        throw "DeepCool executable not found: $deepCoolExe"
    }

    Get-Process DeepCool -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process -FilePath $deepCoolExe -ArgumentList "--remote-debugging-port=$debugPort" -WindowStyle Hidden

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        Hide-DeepCoolWindows
        $page = Get-DeepCoolPage
        if ($page) {
            return $page
        }
    }

    throw 'DeepCool DevTools port did not become available.'
}

function Stop-DeepCoolAppAfterOff {
    Start-Sleep -Seconds 2
    Get-Process DeepCool -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Log 'DeepCool app stopped after Off to fully darken the LQ094 panel.'
}

function Invoke-DeepCoolCdpExpression {
    param(
        [string]$WebSocketUrl,
        [string]$Expression
    )

    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    try {
        $client.ConnectAsync([Uri]$WebSocketUrl, [Threading.CancellationToken]::None).Wait()
        $request = @{
            id = 1
            method = 'Runtime.evaluate'
            params = @{
                expression = $Expression
                awaitPromise = $true
                returnByValue = $true
                timeout = 15000
            }
        } | ConvertTo-Json -Depth 50 -Compress

        $bytes = [Text.Encoding]::UTF8.GetBytes($request)
        $client.SendAsync(
            [ArraySegment[byte]]::new($bytes),
            [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            [Threading.CancellationToken]::None
        ).Wait()

        while ($true) {
            $buffer = New-Object byte[] 1048576
            $stream = [IO.MemoryStream]::new()
            do {
                $result = $client.ReceiveAsync(
                    [ArraySegment[byte]]::new($buffer),
                    [Threading.CancellationToken]::None
                ).Result
                $stream.Write($buffer, 0, $result.Count)
            } while (-not $result.EndOfMessage)

            $message = [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
            if ($message.id -eq 1) {
                return $message
            }
        }
    } finally {
        $client.Dispose()
    }
}

$page = Get-DeepCoolPage
if (-not $page) {
    Write-Log 'DeepCool CDP not available; restarting DeepCool with debug port.'
    $page = Start-DeepCoolWithDebugPort
}

$escapedBackupPath = ($backupPath -replace '\\', '\\')
$stateExpression = $null

if ($State -eq 'Off') {
    $stateExpression = @"
(async () => {
  const sn = '$serialNumber';
  const current = await window.ipcRenderer.invoke('LQ094/get-device-info', sn);
  if (!current || current.code !== 0) {
    return JSON.stringify({ ok: false, stage: 'get', current });
  }
  const fs = require('fs');
  const currentOptions = current.data && current.data.options ? current.data.options : {};
  const looksOn = currentOptions.screenStatus === 1 || currentOptions.screenBrightness > 0;
  if (looksOn) {
    fs.writeFileSync('$escapedBackupPath', JSON.stringify(current.data, null, 2), 'utf8');
  }
  const next = JSON.parse(JSON.stringify(current.data));
  next.options.screenStatus = 0;
  next.options.screenBrightness = 0;
  next.options.temperatureDisplay = 0;
  next.options.gyroStatus = 0;
  next.options.noLoadScreen = 0;
  next.recorderMode.cpuClock = 0;
  next.recorderMode.cpuTemperature = 0;
  const updated = await window.ipcRenderer.invoke('LQ094/update-device-info', next);
  return JSON.stringify({ ok: true, state: 'Off', update: updated });
})()
"@
} else {
    $stateExpression = @"
(async () => {
  const fs = require('fs');
  const sn = '$serialNumber';
  let next;
  if (fs.existsSync('$escapedBackupPath')) {
    next = JSON.parse(fs.readFileSync('$escapedBackupPath', 'utf8'));
  } else {
    const current = await window.ipcRenderer.invoke('LQ094/get-device-info', sn);
    if (!current || current.code !== 0) {
      return JSON.stringify({ ok: false, stage: 'get', current });
    }
    next = current.data;
    next.options.screenStatus = 1;
    if (!next.options.screenBrightness || next.options.screenBrightness < 1) {
      next.options.screenBrightness = 30;
    }
  }
  next.options.screenStatus = 1;
  if (!next.options.screenBrightness || next.options.screenBrightness < 1) {
    next.options.screenBrightness = 30;
  }
  next.options.noLoadScreen = 1;
  next.options.gyroStatus = 1;
  next.options.temperatureDisplay = 1;
  next.recorderMode.cpuClock = 1;
  next.recorderMode.cpuTemperature = 1;
  const updated = await window.ipcRenderer.invoke('LQ094/update-device-info', next);
  return JSON.stringify({ ok: true, state: 'On', update: updated });
})()
"@
}

$response = Invoke-DeepCoolCdpExpression -WebSocketUrl $page.webSocketDebuggerUrl -Expression $stateExpression
$value = $response.result.result.value
Write-Log "DeepCool LQ094 $State response: $value"
if ($State -eq 'Off') {
    Stop-DeepCoolAppAfterOff
} else {
    Start-Sleep -Seconds 8
    $page = Get-DeepCoolPage
    if ($page) {
        $retryResponse = Invoke-DeepCoolCdpExpression -WebSocketUrl $page.webSocketDebuggerUrl -Expression $stateExpression
        $retryValue = $retryResponse.result.result.value
        Write-Log "DeepCool LQ094 On delayed retry response: $retryValue"
    } else {
        Write-Log 'DeepCool LQ094 On delayed retry skipped: CDP page not available.'
    }
    Hide-DeepCoolWindowsFor -Seconds 8
    Write-Log 'DeepCool app left running after On to keep the LQ094 panel active.'
}
