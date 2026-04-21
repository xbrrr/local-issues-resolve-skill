---
name: local-issues-resolve
description: Troubleshoot local Windows gaming and performance issues with evidence-first diagnostics and safe rollback steps. Use when the user reports stutters, freezes, driver latency issues, PresentMon or LatencyMon logs, or asks to optimize local system behavior.
---
# Local Issues Resolve

## Goal
Resolve local performance and stability issues quickly with minimal-risk changes, measurable before/after checks, and explicit rollback points.

## Workflow
1. Confirm symptom scope:
   - app or game name
   - when the issue happens
   - what changed recently
2. Gather evidence before tuning:
   - analyze the latest `PresentMon` CSV for frametime percentiles, spike count, and spike shape
   - read the `LatencyMon` summary for top DPC or ISR offenders and hard pagefault leaders
   - classify spike frames as mostly CPU-side (`MsCPUBusy`, `MsCPUWait`) or GPU-side (`MsGPUWait`, `MsGPUTime`)
3. Apply the smallest reversible change first:
   - avoid broad system rewrites
   - change one variable at a time
   - keep account and profile parity when a game has multiple profiles
4. Re-test and compare:
   - run a short repeatable session
   - compare new logs against the prior baseline
   - keep only changes that measurably help

## Prioritization Rules
- If baseline frametime is good but rare spikes are huge, treat it as burst, driver, or background contention first.
- If `MsGPUTime` is low on spike frames and `MsCPUBusy` is high, prioritize CPU scheduling and background isolation.
- If `MsGPUWait` or `MsGPUTime` dominate spikes, prioritize the graphics path, rendering load, and driver settings.
- Treat `PresentMode: Other` and `Composed: Flip` spikes carefully because they can include menu or alt-tab transitions.

## Safe Change Ladder
1. Session hygiene:
   - close non-essential overlays, recorders, and launchers
   - verify the game is using the intended fullscreen path
2. Game config consistency:
   - align the active profile or account
   - lock critical values such as `fps_max`, display mode, and refresh rate
3. Driver and system knobs:
   - toggle one setting at a time
   - document the previous value before changing it
   - if admin access is unavailable, report the exact command instead of improvising
4. Background process isolation:
   - identify the top hard-pagefault or CPU offender
   - test without non-essential startup items first

## Communication Style
- Report facts before theories.
- Separate what changed, what likely helped, and what is still unproven.
- Keep recommendations short, reversible, and easy to test.

## Guardrails
- Do not claim a fix without before and after evidence.
- Do not stack many performance tweaks at once.
- Do not edit unrelated files.
- Always include rollback instructions for registry or system changes.
