# Intake Template

Use this shape for the first substantive reply when the user reports local Windows stutter or performance issues.

## Minimal Intake
- `App/Game`: exact title and launcher
- `Symptom`: stutter, freeze, hitch, audio pop, frame pacing, input delay, or crash
- `When`: gameplay, traversal, combat, menus, loading, alt-tab, or desktop-wide
- `What changed`: driver, BIOS, Windows update, overlay, mod, new peripheral, monitor change, memory tweak, or nothing obvious
- `Repro`: always, intermittent, or only after some uptime
- `Artifacts available`: `PresentMon`, `LatencyMon`, Event Viewer, screenshots, config files

## Recommended First Reply
```text
Observed:
- Symptom description from the user, without adding theories.

What I need next:
1. One short reproducible test case.
2. The latest PresentMon CSV, if available.
3. A LatencyMon summary screenshot or pasted summary, if available.
4. Confirmation of any recent driver, BIOS, overlay, or monitor changes.

Likely bottleneck:
- Mark as unknown until evidence exists, or state the leading hypothesis with a confidence qualifier.

Next test:
1. Smallest reversible experiment.

Rollback:
- Exact setting or command to revert if the change does not help.
```

## Intake Rules
- Ask for the minimum artifact that will cut uncertainty the most.
- If the user already shared logs, analyze them before asking for more.
- If the issue is clearly profile-specific, request config parity before OS-level tuning.
