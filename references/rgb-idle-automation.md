# RGB And Idle Automation

Use this reference when a Windows PC should turn RGB or device LCDs off with the monitors, then restore them on user activity.

## Design Pattern
- Keep detection and application separate.
- Run the idle/display watcher in the interactive user session so it can observe activity and interact with user-scope apps.
- Run privileged hardware or registry writes through a highest-privilege scheduled task.
- Store the requested state in a small state file such as `pending-state.txt`; let the scheduled task worker read it and apply `On` or `Off`.
- Keep a manual recovery command or task that forces `On`.

## State And Logging
- Use a per-user state directory under `%LOCALAPPDATA%`.
- Log every transition with timestamp, target state, previous power plan, vendor API response, and any skipped component.
- Persist `state.txt` for the last intended state, but do not treat it as proof that hardware changed.
- For each component, verify through the strongest available signal:
  - vendor API response for device LCDs
  - registry values plus service behavior for motherboard RGB
  - app config plus actual readback for hotkey-driven RGB utilities

## Mystic Light / Vendor RGB Registry Pattern
- Back up current vendor registry values before forcing `Off`.
- For `Off`, do not only write black colors; also set the global switch state off when the vendor supports it.
- If a vendor keeper process ignores changes, trigger apply flags as a pulse: set apply to `1`, wait briefly, then return it to `0`.
- If `On` does not physically restore lighting, restart the vendor keeper process after restoring the profile, then reassert the global switch on.
- If `Off` does not physically turn lighting off, avoid restarting the keeper during the off transition if restart causes the app to reload the on profile.
- Do not assume `LEDStatus={0,0,0}` means all lighting is off; compare it with global switch, color profile, and physical/user report.
- For MSI Mystic Light, verify the vendor UI behavior before automating. On some boards, direct registry writes, apply flags, service restarts, OpenRGB, and MSI DLL calls can all report success without changing the physical controller state.
- If the MSI Center UI switch is the only confirmed physical control, keep it in the interactive user session. Do not drive MSI Center UI from a highest-privilege scheduled task; elevated UI automation may see only the top window and miss WebView or WPF child controls.
- A practical Mystic Light split is: user-session watcher invokes an MSI UI worker first, then a highest-privilege worker applies power plan, Dynamic Lighting, device LCDs, and other privileged changes. The elevated worker should explicitly skip Mystic Light UI.
- If UI Automation cannot see the MSI Center `Global switch` element but the window is visible, a coordinate fallback can be acceptable only when it is relative to the MSI Center window, gated by the expected registry state, and verified by reading `GlobalSwitchState` after the click.
- Treat physical confirmation as required for Mystic Light. Registry values, stopped services, black color data, or a successful task exit code are not enough proof that the controller changed state.

## Hotkey-Driven RGB Apps
- If the only reliable control is a hotkey, read the app's state file before and after sending the hotkey.
- Synthetic hotkeys can reset Windows idle time. After a successful `Off`, suppress wake handling for a short window before allowing `On`.
- If the app reports the wrong final state, do not keep toggling blindly; log the mismatch and leave the last known safe state.

## Device LCDs
- Prefer a local API or vendor service endpoint when available.
- Preserve the previous screen options before setting brightness or screen status to off.
- On restore, set both screen status and brightness, not only the mode.

## Validation Checklist
- Scheduled task exists, uses the expected worker script, and has highest privileges.
- Watcher is running in the user session and starts from the intended autostart path.
- Manual `Off -> On` cycle returns success codes.
- Final `On` state restores the previous power plan.
- Logs show no privilege skip for HKLM or vendor-app writes.
- For Mystic Light, run at least three `Off -> On` cycles with MSI Center initially closed. Require all of the following before claiming success: UI worker `ok=True`, `GlobalSwitchState` matches the target after every step, MSI Center closes after automation, and the final state is `On`.
- A real monitor-off cycle is still required before claiming unattended success.

## Rollback
- Disable or remove the watcher autostart entry.
- Disable the scheduled task.
- Run the manual `On` path.
- Restore the backed-up vendor profile or reapply the profile from the vendor UI.
