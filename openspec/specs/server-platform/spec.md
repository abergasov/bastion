# Server Platform Specification

## Purpose

Define the reproducible, provider-independent NixOS platform for a new private
VPN server. This is target behavior; no server configuration is implemented yet.

## Requirements

### Requirement: Reproducible NixOS server

Bastion SHALL provide a reproducible NixOS configuration for a new x86_64 server
running OpenVPN, WireGuard, fail2ban and the owner's ssh_notify integration.
Migration of existing VPN credentials and backward compatibility with the previous
server are not required.

#### Scenario: Configure a new server
- **WHEN** the administrator prepares a new host
- **THEN** its services and persistent networking are described by NixOS configuration
- **AND** installation does not depend on importing credentials from the previous server

### Requirement: Small VPS resource target

Bastion SHALL target servers with approximately 1 vCPU, 2 GB RAM and 20 GB of
local disk for the expected personal VPN workload. This is a deployment and
verification target, not a measured minimum or a guarantee of VPN throughput.
Installation, normal service operation and system updates SHALL be verified on
this resource class, including memory use and disk headroom. Any swap or external
build resources needed by the verified workflow SHALL be documented. A specific
provider plan, price or traffic allowance is not required.

#### Scenario: Verify the target resource class
- **WHEN** implementation readiness is assessed for a host with approximately 1 vCPU, 2 GB RAM and 20 GB disk
- **THEN** installation, both VPN services and a system update are checked within those resources
- **AND** observed resource use, VPN throughput and any unverified limits are reported

### Requirement: Provider-independent host configuration

Bastion SHALL support Hetzner initially and keep provider-specific disk, boot and
network details in host configuration so other providers can be used. Routine
administration SHALL NOT require the Hetzner API.

#### Scenario: Use another provider
- **WHEN** a compatible x86_64 host is configured at another provider
- **THEN** provider-specific settings are supplied by that host's configuration
- **AND** the VPN management interface does not require a Hetzner API

### Requirement: Public addressing and automated installation

The server SHALL have public IPv4 and IPv6 addresses and use IP addresses as
connection endpoints without requiring a domain. Installation SHALL be automated
over SSH. The installation tool and concrete public addresses remain open choices.
Both VPNs SHALL provide IPv4 and IPv6 internet access through this server as
specified in [vpn-connectivity](../vpn-connectivity/spec.md); public IPv6
addressing alone does not satisfy that requirement.

#### Scenario: Install an IP-only host
- **WHEN** the administrator starts an authorized installation on a prepared host
- **THEN** installation proceeds through the selected automated SSH workflow
- **AND** a domain name is not a prerequisite
