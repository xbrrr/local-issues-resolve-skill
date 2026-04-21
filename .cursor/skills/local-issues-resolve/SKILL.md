---
name: local-issues-resolve
description: Troubleshoot local Windows gaming/performance issues with evidence-first diagnostics and safe rollback steps. Use when the user reports stutters, freezes, driver latency issues, PresentMon/LatencyMon logs, or asks to optimize local system behavior.
---
# Local Issues Resolve

## Goal
Resolve local performance/stability issues fast, with minimal risky changes and clear rollback points.

## Workflow
1. Confirm symptom scope:
   - app/game names
   - when issue happens (combat/menu/idle)
   - after which recent changes
2. Gather evidence before tuning:
   - analyze latest `PresentMon` CSV (frametime percentiles, spike count, spike mode)
   - read `LatencyMon` summary (top DPC/ISR, hard pagefault leaders)
   - identify whether spikes are mostly CPU-side (`MsCPUBusy/Wait`) or GPU-side (`MsGPUWait/GPUTime`)
3. Apply smallest reversible changes first:
   - avoid broad system rewrites
   - change one variable at a time
   - keep account/profile parity when app has multiple profiles
4. Re-test and compare:
   - short match/session test
   - re-check logs
   - keep only changes that measurably help

## Prioritization Rules
- If frametime baseline is good but rare spikes are huge, treat as burst/driver/background contention.
- If `MsGPUTime` is low on spike frames and `MsCPUBusy` is high, prioritize CPU/background process isolation.
- If `MsGPUWait/GPUTime` dominate spikes, prioritize graphics/driver path and rendering load.
- Treat `PresentMode: Other`/`Composed: Flip` spikes carefully; they can include alt-tab/menu transitions.

## Safe Change Ladder
1. Session hygiene:
   - close overlays/recorders/launchers not required for test
   - ensure true fullscreen path for game
2. Game config consistency:
   - align active profiles/accounts
   - lock critical values (`fps_max`, display mode, refresh)
3. Driver/system knobs (reversible):
   - toggle one setting at a time and document previous value
   - require admin for HKLM edits; if unavailable, report exact command for user
4. Background process isolation:
   - identify top hard-pagefault process and test without it
   - disable only non-essential startup items first

## MSI/Skydimo Game Mode Automation
- Prefer a paired `on/off` script flow for repeatability.
- Keep `SkyDimo.exe` running during gaming if user requests it.
- For MSI Center on modern builds, include UWP process names:
  - `DCv2.exe`
  - `MysticLightController.exe`
  - plus common MSI helpers/services (`MSI_Central_Service.exe`, `MSI_Case_Service.exe`, `MSI.CentralServer.exe`).
- For AMD installer manager handling, include both names:
  - `AMDInstallManager.exe`
  - `AMDRM_InstallManager.exe`

### On Script Pattern
1. Save process restore state to `%TEMP%\cs2_game_mode_state.txt`.
2. Stop MSI services first (`MSI_Center_Service`, `MSI_Case_Service`).
3. Kill targeted MSI/UWP helper processes in two passes (with 1-second delay).
4. Kill user-requested background apps (Perplexity/Codex/Telegram/AnyDesk/AMD manager).
5. Do not kill `SkyDimo.exe` if user asked to keep it alive.

### Off Script Pattern
1. Start MSI services again.
2. Start MSI Center UWP explicitly via:
   - `shell:AppsFolder\9426MICRO-STARINTERNATION.MSICenter_kzh8wxbdkxb8p!App`
3. Start standalone Skydimo from explicit path if present:
   - `C:\Program Files (x86)\Skydimo\SkyDimo.exe --auto_startup`
4. Restore only apps recorded in `%TEMP%\cs2_game_mode_state.txt` (state-aware restore).
5. Avoid directly launching backend service executables that can leave a hanging black console.

### Validation
- After `on`: verify target processes are absent.
- After `off`: verify expected restored apps are present.
- If a process persists, capture exact process name/path and update script by concrete executable name.

## Communication Style
- Report facts first: what logs show, not assumptions.
- Separate:
  - what changed
  - what likely helped
  - what is still unproven
- Keep recommendations in short, testable batches.

## Guardrails
- Do not claim a fix without before/after evidence.
- Do not stack many performance tweaks at once.
- Do not edit unrelated files.
- Always include rollback instructions for registry/system changes.
