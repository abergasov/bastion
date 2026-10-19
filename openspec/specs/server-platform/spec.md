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
this resource class, including memory use and disk headroom. System updates SHALL
be built on the VPS itself. Any required swap SHALL be documented; an external
builder SHALL NOT be silently substituted if on-VPS builds fail. A specific
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
over SSH using `nixos-anywhere` with `disko` for declarative disk partitioning and
formatting. Concrete public addresses SHALL be supplied for each host.
The owner's existing Ed25519 public key is already registered for new VPS creation
and SHALL provide initial SSH access for the owner or installation script; its
private key SHALL remain off the VPS. Initial access to the provider's source OS
SHALL be distinguished from the installed Bastion policy: installation requires
sufficient privileges, while the installed system SHALL enforce `admin`-only SSH
and password-authenticated `su` as specified in
[server-administration](../server-administration/spec.md).
The installation procedure SHALL verify the target host's SSH identity and
required installation privileges before destructive disk operations.
Both VPNs SHALL provide IPv4 and IPv6 internet access through this server as
specified in [vpn-connectivity](../vpn-connectivity/spec.md); public IPv6
addressing alone does not satisfy that requirement.

#### Scenario: Install an IP-only host
- **WHEN** the administrator starts an authorized installation on a prepared host
- **THEN** `nixos-anywhere` installs NixOS over SSH with the `disko` disk configuration
- **AND** initial access uses the owner's existing Ed25519 key and verified installation privileges
- **AND** the installed host permits SSH only as `admin` using the authorized key
- **AND** a domain name is not a prerequisite

### Requirement: Manual updates built on the VPS

Dependencies SHALL be pinned in `flake.lock`. Updates SHALL be initiated manually:
update the locked dependencies, check and build the system on the VPS, apply the
configuration, and verify fresh SSH access and both VPNs. Routine maintenance
SHALL use a weekly window; critical security fixes SHALL be handled outside that
window when needed. The exact day and time SHALL be chosen operationally.
System updates and reboots SHALL NOT run unattended. Required reboots SHALL be
initiated manually during maintenance, followed by SSH and VPN checks.
Privileged activation SHALL follow the `admin` SSH login and password-authenticated
`su` policy. Rollout SHALL preserve a working administrative session as required by
[recovery-and-verification](../recovery-and-verification/spec.md).

#### Scenario: Perform a routine update
- **WHEN** the administrator performs weekly maintenance
- **THEN** dependencies are updated in `flake.lock` and checks and the system build run on the VPS before activation
- **AND** fresh SSH access and both VPNs are checked after activation and any manual reboot
- **AND** a failed build is reported without activating the failed configuration

#### Scenario: Apply a critical security fix
- **WHEN** a critical security fix requires an update before the next weekly window
- **THEN** the administrator performs an out-of-schedule manual update with the same build and connectivity checks
