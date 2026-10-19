# VPN Connectivity Specification

## Purpose

Define the supported VPN transports, clients and full-tunnel behavior for private
internet access. These requirements describe a system still to be implemented.

## Requirements

### Requirement: VPN transports

Bastion SHALL expose OpenVPN on TCP/443 and WireGuard on UDP/443 using IP endpoints.
Documentation SHALL NOT describe TCP/443 as HTTPS or claim that either port
guarantees bypass of traffic filtering, anonymity or absolute security.

#### Scenario: Connect through each protocol
- **WHEN** a device uses a valid profile for its selected VPN protocol
- **THEN** OpenVPN connects to TCP/443 and WireGuard connects to UDP/443
- **AND** neither connection requires a domain name or an HTTPS service

### Requirement: Supported clients and scale

Bastion SHALL support phones, computers and tablets running Android, iOS, Windows,
macOS and Linux with separate VPN credentials per device. Expected use is 2–3
users with 3–4 devices each; Bastion SHALL NOT impose artificial client, device,
bandwidth or traffic quotas.

#### Scenario: Use several devices
- **WHEN** a user enrolls multiple supported devices
- **THEN** each device receives its own VPN identity
- **AND** the expected device count is not enforced as an enrollment quota

### Requirement: Full-tunnel internet and DNS

Both VPNs SHALL carry all client IPv4 and IPv6 internet traffic, including DNS,
through the VPN tunnel and the VPS's internet connection. Both address families
SHALL remain usable through each VPN; disabling IPv6 is not a substitute for
IPv6 tunneling.
VPN client DNS configuration SHALL list Cloudflare `1.1.1.1` first as the default
resolver and Google `8.8.8.8` second as the backup.
Clients SHALL query the selected public resolver directly through the VPN tunnel
and the VPS's internet connection. Bastion SHALL NOT deploy a separate DNS service
or DNS forwarder on the VPS for VPN clients. Both resolver addresses SHALL be
routed through the VPN. Resolver selection and failover depend on the client OS
and VPN application; list order alone SHALL NOT be presented as a guarantee that
Google is used only while Cloudflare is unavailable or that clients immediately
return to Cloudflare after recovery. Failover SHALL be verified on each supported OS.
Client routing and kill-switch enforcement SHALL be configured and tested for
both VPNs on Android, iOS, Windows, macOS and Linux before readiness is declared.
Local-network exceptions remain an open choice and SHALL be specified and tested
per supported operating system; server configuration alone is not proof that
clients cannot bypass the VPN.

#### Scenario: Access the internet with a tunnel established
- **WHEN** a supported client accesses IPv4 and IPv6 internet destinations or sends DNS requests with either VPN established
- **THEN** both address families work through the VPN and the VPS, without direct internet bypass
- **AND** the client queries the selected public resolver directly through the tunnel and the VPS, without a DNS service on the VPS

#### Scenario: Verify dual-stack routing
- **WHEN** each VPN is checked on a supported operating system with native IPv4 and IPv6 available
- **THEN** internet access through both address families is verified to exit through the VPS without bypassing the VPN
- **AND** server public dual-stack addressing alone is not accepted as that verification

#### Scenario: Default DNS resolver is unavailable
- **WHEN** Cloudflare `1.1.1.1` is unreachable through an established VPN tunnel
- **THEN** the supported client can resolve names using Google `8.8.8.8` through that tunnel
- **AND** switching delay and resolver selection after Cloudflare recovers are checked and documented for that client

### Requirement: Block internet access during tunnel loss

When either VPN tunnel is lost, the client SHALL block IPv4 and IPv6 internet
traffic, including DNS, until the tunnel is restored. It SHALL NOT fall back to
direct internet access while reconnecting. The kill switch SHALL permit the
traffic necessary to re-establish the VPN connection without permitting general
internet access outside the tunnel. After restoration, internet traffic SHALL
resume through the VPN and the VPS.

#### Scenario: Tunnel drops
- **WHEN** an established OpenVPN or WireGuard tunnel is interrupted on a supported operating system
- **THEN** IPv4, IPv6 and DNS internet traffic is blocked rather than sent directly through the client's network
- **AND** the block remains effective throughout reconnection attempts, including a change between client networks

#### Scenario: Tunnel is restored
- **WHEN** the VPN tunnel is successfully re-established after an interruption
- **THEN** IPv4 and IPv6 internet access and DNS resolution resume through the VPN and the VPS
- **AND** no direct internet fallback occurs before restoration
