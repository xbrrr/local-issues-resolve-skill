$ErrorActionPreference = 'Stop'

$stateRoot = Join-Path $env:LOCALAPPDATA 'RgbIdleWatcher'
$pendingPath = Join-Path $stateRoot 'msi-mystic-pending-state.txt'
$resultPath = Join-Path $stateRoot 'msi-mystic-result.json'
$logPath = Join-Path $stateRoot 'watcher.log'
$diagnosticTreePath = Join-Path $stateRoot 'msi-mystic-last-ui-tree.txt'
$diagnosticScreenshotPath = Join-Path $stateRoot 'msi-mystic-last-screen.png'
$directScriptPath = Join-Path $PSScriptRoot 'msi-mystic-direct.ps1'
$script:StartedMsiCenterForAutomation = $false

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
}

function Write-Result {
    param(
        [bool]$Ok,
        [string]$Message
    )

    @{
        ok = $Ok
        message = $Message
        timestamp = (Get-Date).ToString('o')
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

function Start-MsiCenterUi {
    Start-Process -FilePath explorer.exe -ArgumentList 'shell:AppsFolder\9426MICRO-STARINTERNATION.MSICenter_kzh8wxbdkxb8p!App'
    $script:StartedMsiCenterForAutomation = $true
    Write-Log 'MSI UI worker requested MSI Center launch.'
}

function Get-MsiCenterWindow {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction SilentlyContinue
    $process = Get-Process -Name DCv2 -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -eq 'MSI Center' } |
        Select-Object -First 1
    if (-not $process) {
        return $null
    }

    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $processCondition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
        $process.Id
    )
    $nameCondition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty,
        'MSI Center'
    )
    $condition = [System.Windows.Automation.AndCondition]::new($processCondition, $nameCondition)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
}

function Wait-MsiCenterWindow {
    param([int]$TimeoutSeconds = 30)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $window = Get-MsiCenterWindow
        if ($window) {
            return $window
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Wait-MsiMysticLightSwitch {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [int]$TimeoutSeconds = 30
    )

    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction SilentlyContinue
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        'cb_MysticLight_OnOff'
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $switch = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($switch) {
            return $switch
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Get-MsiGlobalSwitchState {
    $path = 'HKLM:\SOFTWARE\WOW6432Node\MSI\MSI Center\Component\Mystic Light\LED'
    $value = (Get-ItemProperty -LiteralPath $path -ErrorAction Stop).GlobalSwitchState
    return ($value -eq 'True' -or $value -eq $true)
}

function Invoke-MsiDirectApply {
    param([string]$TargetState)

    if (-not (Test-Path -LiteralPath $directScriptPath)) {
        Write-Log "MSI direct apply skipped: script not found at $directScriptPath."
        return $false
    }

    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $directScriptPath -State $TargetState 2>&1
        $exit = $LASTEXITCODE
        $joined = (($output | ForEach-Object { $_.ToString() }) -join ' | ')
        Write-Log "MSI direct apply target=$TargetState exit=$exit output=$joined"
        return ($exit -eq 0 -and $joined -match 'Set_GlobalSwitch.*=True' -and $joined -match 'Gen1_ApplyBoard.*=True')
    } catch {
        Write-Log "MSI direct apply failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-MsiGlobalSwitchCoordinateFallback {
    param(
        [string]$TargetState,
        [System.Windows.Automation.AutomationElement]$Window
    )

    $desired = ($TargetState -eq 'On')
    $before = Get-MsiGlobalSwitchState
    $clickCount = if ($before -eq $desired) { 2 } else { 1 }
    if ($before -eq $desired) {
        Write-Log "MSI UI worker coordinate fallback forcing reapply: registry already target=$TargetState."
    }

    $source = @'
using System;
using System.Runtime.InteropServices;

public static class MsiClickWin32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
'@
    Add-Type -TypeDefinition $source -ErrorAction SilentlyContinue

    $process = Get-Process -Name DCv2 -ErrorAction Stop | Select-Object -First 1
    $handle = $process.MainWindowHandle
    if ($handle -eq [IntPtr]::Zero) {
        throw 'MSI Center main window handle not found'
    }

    $rect = New-Object MsiClickWin32+RECT
    [void][MsiClickWin32]::GetWindowRect($handle, [ref]$rect)
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 900 -or $height -lt 500) {
        $bounds = $Window.Current.BoundingRectangle
        $rect.Left = [int]$bounds.Left
        $rect.Top = [int]$bounds.Top
        $width = [int]$bounds.Width
        $height = [int]$bounds.Height
    }
    if ($width -lt 900 -or $height -lt 500) {
        throw "MSI Center window is too small for coordinate fallback: ${width}x${height}"
    }

    # MSI Center's Mystic Light global switch is stable in this layout.
    $x = [int]($rect.Left + ($width * 0.646))
    $y = [int]($rect.Top + ($height * 0.197))
    [void][MsiClickWin32]::SetForegroundWindow($handle)
    Start-Sleep -Milliseconds 300
    for ($i = 0; $i -lt $clickCount; $i++) {
        [void][MsiClickWin32]::SetCursorPos($x, $y)
        Start-Sleep -Milliseconds 100
        [MsiClickWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 80
        [MsiClickWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 1500
    }

    $after = Get-MsiGlobalSwitchState
    Write-Log "MSI UI worker coordinate fallback: before=$before after=$after target=$TargetState clicks=$clickCount point=$x,$y size=${width}x${height}."
    return ($after -eq $desired)
}

function Save-MsiDiagnostics {
    param([System.Windows.Automation.AutomationElement]$Window)

    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction SilentlyContinue
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save($diagnosticScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
    } catch {
        Write-Log "MSI UI worker screenshot diagnostic failed: $($_.Exception.Message)"
    }

    try {
        $lines = [System.Collections.Generic.List[string]]::new()
        function Add-UiLine {
            param(
                [System.Windows.Automation.AutomationElement]$Element,
                [int]$Depth,
                [int]$MaxDepth
            )
            if ($Depth -gt $MaxDepth -or -not $Element) {
                return
            }
            $current = $Element.Current
            $rect = $current.BoundingRectangle
            $indent = '  ' * $Depth
            $lines.Add($indent + 'type=' + $current.ControlType.ProgrammaticName + ' name=[' + $current.Name + '] aid=[' + $current.AutomationId + '] class=[' + $current.ClassName + '] rect=[' + $rect.X + ',' + $rect.Y + ',' + $rect.Width + ',' + $rect.Height + ']')
            $children = $Element.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
            foreach ($child in $children) {
                Add-UiLine -Element $child -Depth ($Depth + 1) -MaxDepth $MaxDepth
            }
        }

        Add-UiLine -Element $Window -Depth 0 -MaxDepth 8
        $lines | Set-Content -LiteralPath $diagnosticTreePath -Encoding UTF8
        Write-Log "MSI UI worker saved diagnostics: $diagnosticTreePath"
    } catch {
        Write-Log "MSI UI worker tree diagnostic failed: $($_.Exception.Message)"
    }
}

function Close-MsiCenterIfAutomationStarted {
    if (-not $script:StartedMsiCenterForAutomation) {
        return
    }

    Start-Sleep -Seconds 2
    Get-Process -Name DCv2 -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -eq 'MSI Center' } |
        ForEach-Object {
            $_.CloseMainWindow() | Out-Null
            if (-not $_.WaitForExit(5000)) {
                $_.Kill()
            }
        }
    Write-Log 'MSI UI worker closed MSI Center after automation.'
}

try {
    if (-not (Test-Path -LiteralPath $pendingPath)) {
        throw 'pending MSI Mystic Light state not found'
    }

    $targetState = (Get-Content -LiteralPath $pendingPath -Raw).Trim()
    if ($targetState -notin @('On', 'Off')) {
        throw "invalid MSI Mystic Light state '$targetState'"
    }

    $window = Get-MsiCenterWindow
    if (-not $window) {
        Start-MsiCenterUi
        $window = Wait-MsiCenterWindow -TimeoutSeconds 30
    }
    if (-not $window) {
        throw 'MSI Center window not found'
    }

    $switch = Wait-MsiMysticLightSwitch -Window $window -TimeoutSeconds 5
    if (-not $switch) {
        Save-MsiDiagnostics -Window $window
        if (Invoke-MsiGlobalSwitchCoordinateFallback -TargetState $targetState -Window $window) {
            Write-Result -Ok $true -Message "coordinate fallback target=$targetState"
            return
        }
        throw 'cb_MysticLight_OnOff not found and coordinate fallback failed'
    }

    $toggle = $switch.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
    $desired = if ($targetState -eq 'On') {
        [System.Windows.Automation.ToggleState]::On
    } else {
        [System.Windows.Automation.ToggleState]::Off
    }

    $before = $toggle.Current.ToggleState
    if ($before -ne $desired) {
        $toggle.Toggle()
        Start-Sleep -Milliseconds 1000
    }
    $after = $toggle.Current.ToggleState
    $ok = ($after -eq $desired)
    Write-Log "MSI UI worker switch state: before=$before after=$after target=$targetState."
    Write-Result -Ok $ok -Message "before=$before after=$after target=$targetState"
} catch {
    Write-Log "MSI UI worker failed: $($_.Exception.Message)"
    Write-Result -Ok $false -Message $_.Exception.Message
} finally {
    Close-MsiCenterIfAutomationStarted
}
