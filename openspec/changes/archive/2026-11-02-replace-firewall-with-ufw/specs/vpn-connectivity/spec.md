# Spec Delta

## ADDED Requirements

### Requirement: UFW-managed host and VPN firewall

Bastion SHALL manage its persistent host and VPN firewall through UFW and
Ansible on IPv4 and IPv6. UFW SHALL own Bastion's static ingress, forwarding
and address-translation policy; the previous independent Bastion nftables
policy SHALL NOT remain active after successful migration. fail2ban SHALL
continue to own dynamic SSH bans under the existing administration requirements.

The effective UFW policy SHALL preserve the existing inbound services,
unrestricted outbound traffic, full-tunnel forwarding and client-isolation
requirements. Unsolicited incoming and forwarded traffic SHALL be denied by
default, with explicit VPN-to-uplink forwarding and required control/return
traffic permitted. Packaged defaults or stale rules SHALL NOT expose additional
services or bypass client isolation. Configuration conflicts SHALL be reported
before activation rather than silently accepted or globally flushed.

The firewall SHALL persist across reboot. An unchanged Ansible reapplication
SHALL produce no firewall changes or unnecessary reloads and SHALL preserve
VPN identities, device membership and revocations. Inspection instructions
SHALL cover the complete effective policy, including rules not shown by the
ordinary UFW status listing.

#### Scenario: Install and inspect UFW
- **WHEN** Ansible configures a supported fresh Ubuntu host
- **THEN** UFW is enabled persistently for both address families
- **AND** public TCP/22, TCP/443 and UDP/443 are permitted, subject to authentication and fail2ban, while probes to other listening services are blocked
- **AND** required network control traffic and established/related replies work
- **AND** operator instructions identify how to inspect filtering, forwarding and address translation

#### Scenario: Forward through either VPN
- **WHEN** authenticated OpenVPN and WireGuard test peers send IPv4/IPv6 traffic to destinations outside the VPN pools
- **THEN** forwarding and source translation permit egress through the configured uplink and return traffic reaches the originating peer
- **AND** DNS reachability and the absence of destination/port restrictions are preserved

#### Scenario: Preserve client isolation with connection tracking
- **WHEN** test peers attempt same-VPN or cross-VPN communication through the VPS on IPv4 or IPv6, including traffic matching a pre-existing established/related entry
- **THEN** peer-to-peer traffic is blocked before any general return-traffic allowance can bypass isolation

#### Scenario: Reject conflicting firewall state
- **WHEN** pre-activation inspection finds incompatible pre-existing UFW rules or a competing static firewall configuration
- **THEN** configuration stops with an actionable conflict report before changing the effective firewall
- **AND** it does not report successful convergence or erase unrelated rules

#### Scenario: Reapply and reboot
- **WHEN** unchanged configuration is reapplied and the host subsequently reboots
- **THEN** reapplication has no firewall changes or unnecessary reloads
- **AND** the enabled firewall is loaded before VPN activation, with the same ingress, dual-stack egress and isolation policy
- **AND** credentials, membership and revoked-device denial remain unchanged

### Requirement: Safe transition to UFW

Bastion SHALL prepare SSH access and the complete replacement policy before
activating UFW. Migration SHALL retain the old protective policy until UFW is
active and fresh administrator connectivity is verified while preserving a
working administrative session. Only Bastion's obsolete firewall resources
SHALL be removed; a global firewall reset SHALL NOT be used. Failure before
retirement of the old policy SHALL leave that policy available and SHALL NOT
be reported as a completed migration. Failed UFW activation SHALL NOT permit
new VPN activation without a working firewall.

Migration and subsequent UFW reloads SHALL preserve effective fail2ban SSH
ban/unban behavior for both IP families without changing the packaged jail
thresholds, windows, durations or exemptions. Successful migration SHALL leave
no boot dependency on the removed firewall. Live rollout remains separately
authorized under the recovery-and-verification requirements.

#### Scenario: Migrate an existing Bastion host
- **WHEN** an existing nftables-based Bastion host receives the UFW configuration
- **THEN** SSH is permitted before UFW activation and a fresh authenticated administrative connection succeeds before legacy-policy removal
- **AND** only the obsolete Bastion policy is retired after UFW activation succeeds
- **AND** both VPNs retain connectivity and peer isolation after migration and reboot

#### Scenario: Fail before the old policy is retired
- **WHEN** UFW validation, activation or fresh SSH verification fails during migration
- **THEN** the operation fails without removing the old policy or enabling unprotected VPN listeners
- **AND** the retained administrative session can restore the previous firewall configuration using documented recovery steps

#### Scenario: Preserve active SSH bans
- **WHEN** an IPv4 or IPv6 source is banned by the packaged fail2ban SSH policy during migration or a UFW reload
- **THEN** new SSH connections from that source remain blocked and an unbanned administrator can still connect
- **AND** an ordinary unban restores new SSH access without changing jail policy
