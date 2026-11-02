# VPN handoff checklist

Run this only in `implement-recovery-and-updates`, after separate authorization
for a live VPS. It is not evidence that any item has been run.

- Keep the existing `admin` SSH session open while applying firewall, routing
  or VPN state; prove a fresh host-key-verified `admin` login before closing it.
  If access is lost, use the agreed server-recreation procedure rather than a
  console or unreviewed firewall rollback.
- With protocol-compatible synthetic peers, record an OpenVPN TCP/443 and a
  WireGuard UDP/443 handshake, listener state and the current OpenVPN profile
  fingerprint.
- From each tunnel, record IPv4 and IPv6 forwarding, a controlled dual-stack
  IPv6 selection, and a successful IPv4-only/fallback connection. The evidence
  must state that client applications choose their own address family.
- Query `1.1.1.1` and `8.8.8.8` through each tunnel and retain the observed
  output. Confirm no local DNS service was introduced.
- Run the IPv4 and IPv6 isolation matrix: WireGuard-to-WireGuard,
  OpenVPN-to-OpenVPN, and each cross-protocol direction must fail while an
  unrelated internet destination remains reachable.
- On the 1-vCPU resource class, retain duration, byte counts and CPU evidence
  for OpenVPN throughput using the [measurement plan](../../../docs/vpn-connectivity.md#throughput-and-cpu-measurement-plan).
  Record package versions, negotiated cipher and actual DCO/fallback state;
  check current Ubuntu security fixes before acceptance. Do not state an
  unmeasured throughput limit.
- Recheck fresh SSH, both VPNs and state validation after any package update or
  reboot. A missing, unreadable, invalid or expired CRL is a failure, not a
  readiness result.
