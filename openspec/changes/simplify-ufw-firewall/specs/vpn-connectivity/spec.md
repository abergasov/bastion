# Spec Delta

## MODIFIED Requirements

### Requirement: Inbound services and unrestricted outbound traffic

Bastion SHALL permit inbound connections to TCP/22, TCP/80, TCP/443, the
configured Ansible SSH port, and the configured VPN endpoints on both IPv4 and
IPv6. The configured Ansible SSH port supplements TCP/22 when it differs. The
firewall SHALL allow established/related return traffic and control traffic
required for correct IPv4/IPv6 operation.

Bastion SHALL NOT impose outbound destination or port restrictions on traffic
originating from the VPS or forwarded from authenticated VPN clients. It SHALL
NOT add a special denylist for provider private or metadata networks. The
server-side client isolation requirement below SHALL still apply within and
across both VPNs. VPN address pools and routing details SHALL be selected during
implementation to satisfy forwarding and isolation requirements.

#### Scenario: Restrict inbound services
- **WHEN** an external peer attempts new IPv4 or IPv6 connections to the VPS
- **THEN** TCP/22, TCP/80, TCP/443, the configured Ansible SSH port, OpenVPN TCP/443 and WireGuard UDP/443 are permitted, subject to authentication and fail2ban where applicable
- **AND** probes to other listening services are blocked while required control traffic and established/related replies remain permitted

#### Scenario: Allow outbound traffic while preserving peer isolation
- **WHEN** the VPS or an authenticated VPN client initiates outbound traffic
- **THEN** Bastion applies no outbound destination or port restriction
- **AND** traffic between VPN clients remains blocked as required below

### Requirement: UFW-managed host and VPN firewall

Bastion SHALL manage its persistent host and VPN firewall through UFW and
Ansible on IPv4 and IPv6. UFW SHALL own Bastion's static ingress, forwarding
and address-translation policy. fail2ban SHALL continue to own dynamic SSH bans
under the existing administration requirements.

The effective UFW policy SHALL deny unsolicited incoming and forwarded traffic
by default, permit unrestricted outbound traffic, and explicitly permit each VPN
tunnel to forward to the configured uplink. IPv4/IPv6 peer-isolation drops SHALL
precede a general established/related forward allowance, and address translation
shall preserve both VPNs' dual-stack egress. Ansible SHALL use direct UFW tasks
for package installation, defaults, ingress, routes and a single enablement; it
SHALL NOT maintain Bastion-specific state manifests, interrupted-apply recovery
or foreign-policy acceptance guards.

The firewall SHALL persist across reboot. Ansible reapplication SHALL preserve
the effective firewall policy, VPN identities, device membership and revocations.
Inspection instructions SHALL cover the complete effective policy, including
rules not shown by ordinary UFW status output.

#### Scenario: Apply the UFW policy
- **WHEN** Ansible configures a supported Ubuntu host
- **THEN** it permits the specified inbound services and VPN-to-uplink forwarding before enabling UFW once for both address families
- **AND** the active policy preserves dual-stack NAT, control/return traffic and VPN client isolation

#### Scenario: Forward through either VPN
- **WHEN** authenticated OpenVPN and WireGuard test peers send IPv4/IPv6 traffic to destinations outside the VPN pools
- **THEN** forwarding and source translation permit egress through the configured uplink and return traffic reaches the originating peer
- **AND** DNS reachability and the absence of destination/port restrictions are preserved

#### Scenario: Preserve client isolation with connection tracking
- **WHEN** test peers attempt same-VPN or cross-VPN communication through the VPS on IPv4 or IPv6, including traffic matching a pre-existing established/related entry
- **THEN** peer-to-peer traffic is blocked before any general return-traffic allowance can bypass isolation

#### Scenario: Reapply and reboot
- **WHEN** unchanged configuration is reapplied and the host subsequently reboots
- **THEN** the enabled firewall is loaded before VPN activation with the same ingress, dual-stack egress and isolation policy
- **AND** credentials, membership and revoked-device denial remain unchanged

### Requirement: Safe transition to UFW

Bastion SHALL add the configured SSH allowance before enabling UFW. The role
SHALL NOT reset UFW globally, adopt or validate arbitrary pre-existing firewall
state, retain an interrupted-apply journal, or remove independently managed
firewall resources. Existing-host migration and recovery remain an operator
procedure authorized separately from this role's declarative application.

UFW activation and subsequent reapplication SHALL preserve effective fail2ban
SSH ban/unban behavior for both IP families without changing the packaged jail
thresholds, windows, durations or exemptions. Live rollout remains separately
authorized under the recovery-and-verification requirements.

#### Scenario: Enable UFW after SSH allowance
- **WHEN** the firewall role applies to a host over SSH
- **THEN** the configured SSH port allowance exists before UFW is enabled
- **AND** the role enables UFW once without a global reset or a fresh-connection migration probe

#### Scenario: Preserve active SSH bans
- **WHEN** an IPv4 or IPv6 source is banned by the packaged fail2ban SSH policy during a UFW reapplication
- **THEN** new SSH connections from that source remain blocked and an unbanned administrator can still connect
- **AND** an ordinary unban restores new SSH access without changing jail policy
