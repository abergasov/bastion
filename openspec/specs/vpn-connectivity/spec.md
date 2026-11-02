# VPN Connectivity Specification

## Purpose

Define server-side VPN transports, IPv4/IPv6 forwarding, DNS settings and client
isolation. End-user application selection and device configuration are outside
Bastion's scope. Requirements define acceptance criteria, not verification results.

## Requirements

### Requirement: VPN transports

Bastion SHALL expose OpenVPN on TCP/443 and WireGuard on UDP/443 using IP endpoints.
Documentation SHALL NOT describe TCP/443 as HTTPS or claim that either port
guarantees bypass of traffic filtering, anonymity or absolute security.

#### Scenario: Connect through each protocol
- **WHEN** a protocol-compatible test peer uses a valid profile for its selected VPN protocol
- **THEN** OpenVPN connects to TCP/443 and WireGuard connects to UDP/443
- **AND** neither connection requires a domain name or an HTTPS service

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
- **AND** required network control traffic and established/related replies remain permitted

#### Scenario: Allow outbound traffic while preserving peer isolation
- **WHEN** the VPS or an authenticated VPN client initiates outbound traffic
- **THEN** Bastion applies no outbound destination or port restriction
- **AND** traffic between VPN clients remains blocked as required below

### Requirement: OpenVPN performance priority

OpenVPN configuration SHALL prioritize maximum practical throughput on the target
VPS resource class while preserving encryption, authentication, server fingerprint
pinning, revocation and client isolation. The agreed TCP/443 transport SHALL
remain in use. Cipher selection, compression policy, control-channel protection
(including whether to use tls-crypt-v2) and supported acceleration SHALL be
implementation choices informed by current upstream documentation and measurement
on the target VPS, not additional owner configuration decisions.

#### Scenario: Select and verify OpenVPN parameters
- **WHEN** implementation selects OpenVPN performance settings
- **THEN** it records the selected settings, measures throughput and CPU use on the target resource class, and reports any unverified limits
- **AND** performance tuning preserves the required security and connectivity behavior

### Requirement: OpenVPN profile server fingerprint

Generated OpenVPN profiles SHALL contain exactly the current server certificate's
SHA-256 fingerprint using `peer-fingerprint`. The fingerprint SHALL come from the
certificate issued on the administrator's computer and be included in the locally
generated `.ovpn` profile. No separate fingerprint file is required. Profile
export SHALL NOT omit the pin or substitute a stale fingerprint for compatibility
with a particular application. Application support for and enforcement of the pin
are the user's responsibility, not a Bastion readiness criterion.

#### Scenario: Export a profile for the current server
- **WHEN** an OpenVPN profile is generated
- **THEN** its `peer-fingerprint` contains only the current locally issued server certificate's SHA-256 fingerprint
- **AND** the fingerprint is not learned from a remote server during connection

### Requirement: User-owned applications and device configuration

Users MAY choose any application compatible with the configured VPN protocol.
Bastion SHALL NOT mandate applications or certify compatibility across Android,
iOS, Windows, macOS and Linux. Users are responsible for profile import, device
routing and DNS behavior, kill switches, local-network access restrictions,
server identity verification and replacement of old profiles after recreation.
Bastion SHALL NOT configure or test these behaviors on end-user devices, nor
claim that server configuration prevents direct internet or DNS bypass on them.
Server verification MAY use protocol-compatible test peers without creating a
supported application or OS matrix.

#### Scenario: Use a user-selected application
- **WHEN** a user chooses an application for their device
- **THEN** the user is responsible for compatibility and correct application of the supplied profile
- **AND** application selection and device-side protection checks are not Bastion acceptance requirements

### Requirement: Device identities and scale

Bastion SHALL provide separate VPN credentials per device. Expected use is 2–3
users with 3–4 devices each; Bastion SHALL NOT impose artificial client, device,
bandwidth or traffic quotas.

#### Scenario: Use several devices
- **WHEN** a user enrolls multiple devices
- **THEN** each device receives its own VPN identity
- **AND** the expected device count is not enforced as an enrollment quota

### Requirement: Server-side full-tunnel support and DNS settings

Both VPNs SHALL support forwarding IPv4 and IPv6 internet traffic received through
the tunnel, including DNS, via the VPS's internet connection. Disabling IPv6 is
not a substitute for IPv6 tunneling. Server-advertised settings and generated
profiles SHALL provide full-tunnel routing settings for both address families
where applicable to the protocol, with Cloudflare `1.1.1.1` listed first and
Google `8.8.8.8` second for DNS. Bastion SHALL NOT deploy a separate DNS service
or DNS forwarder on the VPS for clients. Both public resolver addresses SHALL be
reachable through each tunnel. Actual routing, resolver selection, failover and
leak prevention on the user's device remain the user's responsibility; list
order SHALL NOT be presented as a guarantee of exclusive Cloudflare use or
immediate return to Cloudflare after recovery.

#### Scenario: Verify server forwarding through both VPNs
- **WHEN** a test peer sends IPv4 and IPv6 internet traffic through each VPN
- **THEN** both address families are forwarded through the VPS's internet connection
- **AND** having public IPv4/IPv6 addresses alone is not accepted as proof of tunnel forwarding

#### Scenario: Verify DNS settings and reachability
- **WHEN** generated profiles, server-advertised settings and DNS traffic through each VPN are checked
- **THEN** DNS settings list Cloudflare first and Google second, and test queries can reach each resolver through the tunnel
- **AND** no DNS service or forwarder for VPN clients runs on the VPS

### Requirement: Prefer IPv6 for outbound connections

IPv6 SHALL be the preferred outbound address family when the destination and
path support it. IPv4 SHALL remain available for IPv4-only destinations and
fallback when IPv6 cannot establish a connection. Bastion SHALL preserve this
preference wherever its configuration controls destination address selection;
it SHALL NOT enforce preference by blocking or deliberately delaying IPv4.

For forwarded VPN traffic, destination address selection belongs to the client
OS or application. Bastion SHALL provide working IPv6 egress through the VPS
and retain IPv4 forwarding in both VPNs. Documentation SHALL explain that VPS
address-selection settings and the VPN endpoint's address family do not force
clients to choose IPv6. Client preference and connection racing (such as Happy
Eyeballs) remain user-owned behavior, not a guarantee that every dual-stack
connection uses IPv6. No reduction in CAPTCHA frequency SHALL be guaranteed.

#### Scenario: Prefer IPv6 through each VPN
- **WHEN** a controlled test peer with IPv6 preference connects through each VPN to a dual-stack test destination with working IPv6
- **THEN** its selected IPv6 connection exits through the VPS's IPv6 connectivity
- **AND** the result is not presented as proof that all end-user applications select IPv6

#### Scenario: Retain IPv4 fallback through each VPN
- **WHEN** a controlled test peer connects through each VPN to an IPv4-only destination or selects IPv4 after an IPv6 connection failure
- **THEN** its IPv4 connection succeeds through the VPS
- **AND** IPv6 preference does not block IPv4 forwarding

### Requirement: Server-side client isolation

Bastion SHALL block IPv4 and IPv6 traffic through the VPS between VPN clients,
both within each VPN and between OpenVPN and WireGuard, including devices
belonging to the same user. Access to a device's local network outside the tunnel
is controlled by the user and is outside the server's isolation guarantee.

#### Scenario: Attempt communication between VPN clients
- **WHEN** a test peer attempts IPv4 or IPv6 communication through the VPS with another VPN peer in the same VPN or the other VPN
- **THEN** the communication is blocked, including between devices owned by the same user

### Requirement: UFW-managed host and VPN firewall

Bastion SHALL manage its persistent host and VPN firewall through UFW and
Ansible on IPv4 and IPv6. UFW SHALL own Bastion's static ingress, forwarding
and address-translation policy. fail2ban SHALL continue to own dynamic SSH bans
under the existing administration requirements.

The effective UFW policy SHALL deny unsolicited incoming and forwarded traffic
by default, permit unrestricted outbound traffic, and explicitly permit each
VPN tunnel to forward to the configured uplink. IPv4/IPv6 peer-isolation drops
SHALL precede a general established/related forward allowance, and address
translation shall preserve both VPNs' dual-stack egress. Ansible SHALL use
direct UFW tasks for package installation, defaults, ingress, routes and a
single enablement; it SHALL NOT maintain Bastion-specific state manifests,
interrupted-apply recovery or foreign-policy acceptance guards.

The firewall SHALL persist across reboot. Ansible reapplication SHALL preserve
the effective firewall policy, VPN identities, device membership and revocations.
Inspection instructions SHALL cover the complete effective policy, including
rules not shown by the ordinary UFW status listing.

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
- **THEN** the enabled firewall is loaded before VPN activation, with the same ingress, dual-stack egress and isolation policy
- **AND** credentials, membership and revoked-device denial remain unchanged

### Requirement: Safe transition to UFW

Bastion SHALL add TCP/22 and the configured Ansible SSH allowance before
enabling UFW. The role SHALL NOT reset UFW globally, adopt or validate arbitrary
pre-existing firewall state, retain an interrupted-apply journal, or remove
independently managed firewall resources. Existing-host migration and recovery
remain an operator procedure authorized separately from this role's declarative
application.

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
