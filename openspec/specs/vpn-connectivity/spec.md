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

Both VPNs SHALL carry all client internet traffic, including DNS, through the VPN.
VPN client DNS configuration SHALL list Cloudflare `1.1.1.1` first as the default
resolver and Google `8.8.8.8` second as the backup.
Clients SHALL query the selected public resolver directly through the VPN tunnel
and the VPS's internet connection. Bastion SHALL NOT deploy a separate DNS service
or DNS forwarder on the VPS for VPN clients. Both resolver addresses SHALL be
routed through the VPN. Resolver selection and failover depend on the client OS
and VPN application; list order alone SHALL NOT be presented as a guarantee that
Google is used only while Cloudflare is unavailable or that clients immediately
return to Cloudflare after recovery. Failover SHALL be verified on each supported OS.
IPv6 routing, kill-switch behavior and local-network exceptions SHALL be
specified and tested per supported operating system before readiness is declared;
disabling IPv6 only on the server is not proof that clients cannot bypass the VPN.

#### Scenario: Access the internet with a tunnel established
- **WHEN** a supported client sends internet traffic or DNS requests through either VPN
- **THEN** that traffic traverses the VPN
- **AND** the client queries the selected public resolver directly through the tunnel and the VPS, without a DNS service on the VPS

#### Scenario: Verify IPv6 and tunnel-loss behavior
- **WHEN** the implementation is checked on a supported operating system with IPv6 available
- **THEN** client behavior is checked for IPv6 bypass and against the agreed tunnel-loss policy
- **AND** server public dual-stack addressing alone is not accepted as that verification

#### Scenario: Default DNS resolver is unavailable
- **WHEN** Cloudflare `1.1.1.1` is unreachable through an established VPN tunnel
- **THEN** the supported client can resolve names using Google `8.8.8.8` through that tunnel
- **AND** switching delay and resolver selection after Cloudflare recovers are checked and documented for that client
