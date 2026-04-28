# Windows Startup And Power Policy

Use this reference when optimizing a Windows gaming/media PC for low background noise without breaking 24/7 services.

## Startup Cleanup
- Inventory both common autostart locations:
  - Task Manager startup entries and StartupApproved registry state
  - Run keys under HKCU and HKLM
  - Startup folders
  - scheduled tasks with logon triggers
- Preserve explicitly required utilities and security tools.
- Disable rather than delete when possible.
- Keep a before/after list so rollback is easy.

## Power Button Policy
- For a PC that must not sleep or shut down on accidental case-button press, set the short power-button action to `Do nothing`.
- Explain that a long physical press still forces hardware power-off at the firmware/board level; Windows policy does not disable that emergency behavior.
- Do not use sleep or hibernate if media-server availability is required.

## Display-Off Without Sleep
- Set display timeout independently from sleep timeout.
- Keep sleep and hibernation disabled for 24/7 hosts unless the user explicitly accepts downtime.
- Use display-off events or idle time as a trigger for optional RGB, LCD, and idle power-plan automation.

## USB Selective Suspend
- USB selective suspend allows Windows to power down idle USB devices.
- It can save a little power but may cause reconnects, RGB controller issues, audio device pops, or input wake problems on some systems.
- For gaming rigs with device-control problems, test disabling it as a reversible change.

## Idle Power Plan
- Create a separate idle plan instead of weakening the active gaming plan.
- In the idle plan:
  - keep sleep and hibernate off
  - reduce CPU minimum state
  - keep CPU maximum at 100 percent
  - allow PCIe Link State Power Management if stable
  - keep network available
- Restore the previous plan on user activity.

## Validation
- Confirm current active power scheme after every automated transition.
- Confirm display timeout, sleep timeout, hibernate timeout, USB selective suspend, and power-button action explicitly.
- For server workloads, test local and external availability while the display is off.
