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
