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
DNS SHALL use a public resolver accepted by the owner: `1.1.1.1` or `8.8.8.8`.
The final resolver and direct configuration versus a server-side forwarder remain
open. IPv6 routing, kill-switch behavior and local-network exceptions SHALL be
specified and tested per supported operating system before readiness is declared;
disabling IPv6 only on the server is not proof that clients cannot bypass the VPN.

#### Scenario: Access the internet with a tunnel established
- **WHEN** a supported client sends internet traffic or DNS requests through either VPN
- **THEN** that traffic traverses the VPN
- **AND** DNS reaches the selected public resolver through the tunnel

#### Scenario: Verify IPv6 and tunnel-loss behavior
- **WHEN** the implementation is checked on a supported operating system with IPv6 available
- **THEN** client behavior is checked for IPv6 bypass and against the agreed tunnel-loss policy
- **AND** server public dual-stack addressing alone is not accepted as that verification
