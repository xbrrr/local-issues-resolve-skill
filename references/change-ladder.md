# Safe Change Ladder

Use this reference to choose the next experiment. Stay near the top of the ladder unless evidence clearly points lower.

## Tier 1: Zero-Risk Validation
- Confirm the exact repro path.
- Verify active game profile, account, config file, and launcher arguments.
- Check display mode, refresh rate, VRR status, and whether the game is using the intended fullscreen path.
- Close non-essential overlays, capture tools, RGB utilities, browser tabs, and background launchers.

## Tier 2: Reversible App-Level Changes
- Lock or align frame cap, display mode, upscaler mode, and shader cache behavior.
- Disable only one overlay, recorder, mod, or injector at a time.
- Test with a clean game profile if the symptom may be config-specific.

## Tier 3: Reversible Driver Or Windows Toggles
- Change one graphics driver setting at a time.
- Test HAGS, VRR, MPO-sensitive overlays, polling-heavy utilities, or Game Bar related features only when the evidence supports them.
- Document the exact prior state before each toggle.

## Tier 4: Background Isolation
- Isolate the top CPU, DPC, ISR, or hard-pagefault offender first.
- Prefer disabling non-essential startup items or services over broad system cleanup.
- Keep security-sensitive or enterprise-managed services untouched unless the user explicitly asks and understands the tradeoff.

## Tier 5: Higher-Risk Changes
- Driver clean install, BIOS changes, memory tuning, or registry edits belong here.
- Require stronger evidence and always provide rollback steps.
- If admin access is unavailable, provide the exact command or navigation path instead of improvising partial edits.

## Rollback Format
- `Changed`: exact setting, service, command, or file
- `Previous state`: the value before the test
- `Rollback`: precise steps to revert
