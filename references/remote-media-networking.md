# Remote Media Networking

Use this reference when a Windows PC hosts a media server or remote-download service that must be reachable from a trusted network or the internet.

## Public Reachability Triage
- Verify the service is listening locally first: loopback, LAN address, and Windows firewall.
- Verify the router WAN address is truly public. If the router WAN is private, CGNAT, or another router, internet forwarding will not work until the upstream layer is handled.
- In double-NAT setups, forward the same service through each router in the chain:
  - upstream router external port to downstream router WAN address
  - downstream router external port to the Windows host LAN address
- Do not set router DMZ as the first fix.
- If a router field named `remote host` exists, treat it as an allowed source filter, not the internal destination, unless the router documentation says otherwise.

## Plex-Style Remote Access
- Forward only the media-server port required by the application.
- Keep the media-server account secured with strong credentials and two-factor authentication where supported.
- Validate from outside the LAN, not from the same Wi-Fi through NAT loopback.
- If a local VPN is enabled on the host, distinguish these cases:
  - inbound port forwarding to the host still reaches the service because the service listens on the LAN interface
  - outbound service registration or metadata may exit through the VPN unless bypassed
  - firewall rules may need to allow the service on private networks

## VPN Bypass Pattern
- Prefer app-native split tunneling or rule-based routing when available.
- Bypass by process name only when the VPN client supports it reliably.
- If process bypass is not available, use destination-domain or destination-IP rules for service registration endpoints and local subnet rules for LAN traffic.
- Avoid watcher scripts for VPN bypass unless the VPN client overwrites routing or rules on reconnect and has no persistent configuration.
- When restarting a VPN that the agent depends on, expect tool connectivity loss and coordinate manual reconnect.

## Remote Torrent Control
- Prefer a torrent client Web UI reachable only from LAN or a private VPN/mesh network.
- Never expose the Web UI directly to the public internet without an additional secure access layer.
- Use a non-default username and a strong password.
- Separate the Web UI port from the torrent listening port.
- Persist download paths under a predictable media-import directory and keep incomplete downloads separate from completed files.
- Add Windows firewall rules only for the trusted interface scope needed.

## SMB / NAS
- Test reachability and TCP 445 first.
- Let the user enter credentials into native Windows prompts when possible.
- Do not write NAS credentials, private share names, or private IPs into committed skill artifacts.

## Validation Checklist
- Local service URL works.
- LAN client URL works.
- External check works from outside the LAN.
- Windows firewall allows the service.
- Each NAT layer has the correct internal destination.
- VPN on/off behavior is tested separately.
