---
name: local-issues-resolve
description: Troubleshoot local Windows gaming, media-server, and performance issues with evidence-first diagnostics and safe rollback steps. Use when the user reports stutters, freezes, frametime spikes, driver latency issues, hard pagefault bursts, PresentMon or LatencyMon logs, RGB or idle-power behavior, Plex-style 24/7 availability, remote access, or asks to optimize local system behavior without risky blind tweaks.
---
# Local Issues Resolve

## Goal
Resolve local performance and stability issues quickly with minimal-risk changes, measurable before and after checks, and explicit rollback points.

## Quick Start
1. Confirm the symptom scope and ask for the smallest reproducible test.
2. Gather evidence before tuning. Prefer existing `PresentMon`, `LatencyMon`, Event Viewer, or game config artifacts over guesswork.
3. Classify the issue before changing anything:
   - burst frametime spikes with good averages
   - sustained CPU saturation
   - sustained GPU saturation
   - DPC or ISR latency
   - hard pagefault or background contention
   - profile, overlay, or display-path mismatch
4. Apply the smallest reversible change first and retest.
5. Keep only changes that produce measurable improvement.

## Workflow
1. Confirm symptom scope:
   - app or game name
   - when the issue happens
   - what changed recently
   - whether the issue is new, intermittent, or always reproducible
   - whether the symptom is gameplay-only, menu-only, shader-compilation-only, or desktop-wide
2. Gather evidence before tuning:
   - analyze the latest `PresentMon` CSV for frametime percentiles, spike count, and spike shape
   - read the `LatencyMon` summary for top DPC or ISR offenders and hard pagefault leaders
   - classify spike frames as mostly CPU-side (`MsCPUBusy`, `MsCPUWait`) or GPU-side (`MsGPUWait`, `MsGPUTime`)
   - compare active in-game settings, account, config profile, display mode, and refresh path before assuming a system regression
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
- If the stutter started after a driver, BIOS, overlay, or anti-cheat change, verify that timeline before proposing generic tuning.
- If hard pagefault leaders and storage activity line up with spikes, treat memory pressure or background I/O as primary until disproven.

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

## 24/7 Media Server And Idle Power
- For Plex-style hosts, do not use sleep as a power-saving fix unless the user explicitly accepts downtime.
- Prefer display-off, RGB or LCD off, and an idle power plan that keeps network, disks, and services available.
- Preserve hardware transcoding behavior: GPU power saving is acceptable at idle, but the GPU must be allowed to wake when media transcoding needs it.
- Treat port forwarding, router admin changes, SMB credentials, torrent Web UI, and remote-access credentials as sensitive operations. Use placeholders and ask for action-time confirmation before transmitting credentials or opening services to the internet.

## Output Shape
- Start with `Observed`, `Likely Bottleneck`, `Next Test`, and `Rollback`.
- Distinguish evidence from inference explicitly.
- If artifacts are missing, ask only for the minimum next artifact that will meaningfully reduce uncertainty.
- Prefer a short numbered experiment list over a long tweak dump.

## Communication Style
- Report facts before theories.
- Separate what changed, what likely helped, and what is still unproven.
- Keep recommendations short, reversible, and easy to test.

## Guardrails
- Do not claim a fix without before/after evidence.
- Do not stack many performance tweaks at once.
- Do not edit unrelated files.
- Always include rollback instructions for registry or system changes.

## References
- Read [references/intake-template.md](../../../references/intake-template.md) when you need a concise first response or a repeatable evidence request.
- Read [references/presentmon-latencymon.md](../../../references/presentmon-latencymon.md) when you need interpretation rules for frametime spikes, CPU or GPU attribution, or LatencyMon offender triage.
- Read [references/change-ladder.md](../../../references/change-ladder.md) when you are choosing the next safe experiment, especially for overlays, drivers, power settings, HAGS, VRR, polling, storage, or startup isolation.
- Read [references/media-server-idle-remote.md](../../../references/media-server-idle-remote.md) when the task involves Plex-style 24/7 availability, idle power, RGB/LCD-off automation, Wake-on-LAN, router port forwarding, VPN-only admin access, SMB, or remote torrent control.
