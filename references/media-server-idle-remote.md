# Media Server, Idle Power, And Remote Access

Use this reference when a Windows gaming PC is also expected to run as a 24/7 media server.

## Availability Rules
- Do not enable sleep, hibernation, or aggressive disk spin-down when the user needs the server reachable at all times.
- Use display timeout, RGB or LCD-off automation, and an idle power plan instead of system sleep.
- Keep network adapters allowed to stay powered. Only enable Wake-on-LAN if the user accepts that the PC may be off or asleep.
- If the user wants recovery after power loss, recommend BIOS or UEFI `Restore on AC Power Loss = Power On` and a UPS where appropriate.

## Idle Power Pattern
- Keep an explicit high-performance or gaming plan for active use.
- Create a separate idle plan for media-server idle time:
  - sleep and hibernation disabled
  - CPU minimum reduced, CPU maximum left at 100 percent
  - PCIe Link State Power Management enabled if stable
  - display timeout preserved
  - disks kept awake unless the user accepts library wake delays
- Trigger idle mode from user idle time or display-off state, then restore the previous plan on input.
- Expect the GPU to wake for hardware transcoding. Do not force a GPU state that breaks media-server acceleration.

## RGB And Device LCD Pattern
- Prefer vendor-supported APIs, app IPC, or documented service interfaces over raw device writes.
- Back up current state before setting RGB or LCD off.
- Restore the previous state on user activity.
- Avoid editing app LevelDB or binary state while the vendor app is running unless there is no safer path and the user accepts the risk.

## Remote Access Safety
- For media-server remote access, expose only the required service port to the media-server host. Do not use router DMZ.
- Require strong account security and two-factor authentication where the service supports it.
- Verify whether the router WAN address is a public address or behind CGNAT before troubleshooting port forwarding.
- Treat router admin actions, port forwarding, firewall changes, and service exposure as sensitive. Summarize the exact change and ask for confirmation before saving.

## Remote Torrent Control
- Prefer a torrent client Web UI reachable only through a private VPN or mesh network.
- Do not expose torrent Web UI directly to the internet.
- Require a non-default username and strong password.
- Bind or firewall the Web UI to trusted local or VPN interfaces where practical.
- Separate the torrent listening port from the Web UI port; never rely on UPnP for admin interfaces.

## SMB And NAS Access
- Probe reachability and SMB port status without credentials first.
- Let the user type NAS credentials into the native Windows prompt when possible.
- Do not store or transmit NAS usernames, passwords, share paths containing private names, or private IPs in skill artifacts or commits.
