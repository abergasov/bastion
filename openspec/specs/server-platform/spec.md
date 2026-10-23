# Server Platform Specification

## Purpose

Define the provider-independent Ubuntu Server platform configured through Ansible
for a private VPN server. The retained NixOS implementation is historical and
does not implement this baseline.

## Requirements

### Requirement: Repeatable Ubuntu Server configuration

Bastion SHALL configure an ordinary x86_64 Ubuntu Server through Ansible
playbooks and roles, running OpenVPN, WireGuard, fail2ban and the owner's
ssh_notify integration. The local project `/home/alejandro/go/src/ansible`
SHALL serve as a read-only reference; its settings SHALL be checked against
the current specifications before reuse. Needed secrets MAY be copied under
the secret-handling requirements in [recovery-and-verification](../recovery-and-verification/spec.md).
Migration of existing VPN credentials and backward compatibility with the previous
server are not required.

Implementation SHALL select and document a supported Ubuntu Server release,
verify support and component compatibility against official sources, and record
the Ansible and collection versions used. External source artifacts SHALL have
fixed revisions and integrity checks. Routine configuration SHALL NOT implicitly
upgrade the system. Ansible reruns with unchanged inputs SHALL converge without
unnecessary changes, service restarts or credential replacement. This does not
promise bit-for-bit reproducible Ubuntu images.

#### Scenario: Configure a new server
- **WHEN** the administrator prepares a new host
- **THEN** its services and persistent networking are configured through Ansible
- **AND** installation does not depend on importing credentials from the previous server
- **AND** the supported Ubuntu release and automation dependency versions are recorded

#### Scenario: Repeat configuration
- **WHEN** Ansible runs again with unchanged inputs on a configured host
- **THEN** managed state remains unchanged without unnecessary restarts
- **AND** current credentials, membership and revocations remain effective

### Requirement: Small VPS resource target

Bastion SHALL target servers with approximately 1 vCPU, 2 GB RAM and 20 GB of
local disk for the expected personal VPN workload. This is a deployment and
verification target, not a measured minimum or a guarantee of VPN throughput.
Installation, normal service operation and system updates SHALL be verified on
this resource class, including memory use and disk headroom. System updates SHALL
be applied through the manual package/configuration workflow below. Any required
swap SHALL be documented. A specific
provider plan, price or traffic allowance is not required.

#### Scenario: Verify the target resource class
- **WHEN** implementation readiness is assessed for a host with approximately 1 vCPU, 2 GB RAM and 20 GB disk
- **THEN** installation, both VPN services and a system update are checked within those resources
- **AND** observed resource use, VPN throughput and any unverified limits are reported

### Requirement: Provider-independent host configuration

Bastion SHALL support Hetzner initially and keep provider-specific network and
access details in Ansible inventory/host configuration so other providers can be used.
The provider's Ubuntu installation supplies disk layout and boot configuration. Routine
administration SHALL NOT require the Hetzner API.

#### Scenario: Use another provider
- **WHEN** a compatible x86_64 host is configured at another provider
- **THEN** provider-specific settings are supplied by that host's configuration
- **AND** the VPN management interface does not require a Hetzner API

### Requirement: Public addressing and automated provisioning

The server SHALL have public IPv4 and IPv6 addresses and use IP addresses as
connection endpoints without requiring a domain. Provisioning SHALL use Ansible
over SSH to configure the existing Ubuntu installation without repartitioning
disks or replacing the OS. Concrete public addresses SHALL be supplied for each host.
The owner SHALL create the VPS manually in the provider console with Ubuntu Server, IPv4/IPv6
and the owner's public SSH key, enter the host addresses in local configuration,
and initiate installation through a local Make target. The target name is an
implementation detail.
The owner's existing Ed25519 public key is already registered for new VPS creation
and SHALL provide initial SSH access for the owner or installation script; its
private key SHALL remain off the VPS. Bootstrap access using the provider's initial account
SHALL be distinguished from the installed Bastion policy: installation requires
sufficient privileges, while the installed system SHALL enforce `admin`-only SSH
and password-authenticated `su` as specified in
[server-administration](../server-administration/spec.md).
The provisioning procedure SHALL verify the target host's SSH identity and
required privileges before changing state; host-key checking SHALL NOT be disabled.
Subsequent privileged Ansible runs SHALL connect as `admin` and use
password-authenticated `su`; bootstrap access SHALL NOT remain a routine path.
A working administrative session SHALL be preserved until fresh admin access is verified.
Both VPNs SHALL provide IPv4 and IPv6 internet access through this server as
specified in [vpn-connectivity](../vpn-connectivity/spec.md); public IPv6
addressing alone does not satisfy that requirement.

#### Scenario: Provision an IP-only host
- **WHEN** the administrator creates the VPS, configures its addresses locally and starts an authorized installation through the local Make target
- **THEN** Ansible configures the existing Ubuntu installation without disk formatting
- **AND** initial access uses the owner's existing Ed25519 key and verified installation privileges
- **AND** the installed host permits SSH only as `admin` using the authorized key
- **AND** a domain name is not a prerequisite

#### Scenario: Reject an unverified target
- **WHEN** the target's SSH identity or required bootstrap privileges cannot be verified
- **THEN** provisioning fails before changing the server

### Requirement: Manual package and configuration updates

Updates SHALL be initiated manually through the Ansible maintenance workflow:
review package and automation changes, run relevant static and isolated integration
checks, apply the selected updates and configuration, and verify fresh SSH access
and both VPNs. Source revisions and automation dependencies SHALL be updated
explicitly; installed package versions SHALL be recorded for diagnosis and recovery.
Routine maintenance
SHALL use a weekly window; critical security fixes SHALL be handled outside that
window when needed. The exact day and time SHALL be chosen operationally.
Unattended package upgrades and automatic reboots SHALL be disabled, including
any enabled by the base Ubuntu image. Required reboots SHALL be
initiated manually during maintenance, followed by SSH and VPN checks.
Privileged activation SHALL follow the `admin` SSH login and password-authenticated
`su` policy. Rollout SHALL preserve a working administrative session as required by
[recovery-and-verification](../recovery-and-verification/spec.md).

Ansible/package updates SHALL NOT be described as atomic system transactions.
Failures SHALL report partial changes and recovery steps. Supported configuration
reapplication SHALL preserve current credentials and revocations; arbitrary
package downgrades are not a guaranteed rollback mechanism.

#### Scenario: Perform a routine update
- **WHEN** the administrator performs weekly maintenance
- **THEN** reviewed package and configuration updates are applied through Ansible after the relevant checks
- **AND** fresh SSH access and both VPNs are checked after activation and any manual reboot
- **AND** a failed update reports partial changes and recovery steps without claiming successful rollout

#### Scenario: Apply a critical security fix
- **WHEN** a critical security fix requires an update before the next weekly window
- **THEN** the administrator performs an out-of-schedule manual update with the same validation and connectivity checks

### Requirement: Default logs with automatic retention

Bastion SHALL use the default operational logs and logging levels of the selected
Ubuntu services. It SHALL retain logs for 30 days and automatically remove older
logs using native logging and rotation facilities. The retention policy SHALL
cover both the system journal and any service log files used by the deployment,
including the authentication log consumed by ssh_notify if a text log is used.
Secret-exclusion requirements SHALL continue to apply.

#### Scenario: Remove expired logs automatically
- **WHEN** operational logs pass the 30-day retention period
- **THEN** automatic retention cleanup removes expired logs without a manual command
- **AND** rotation and cleanup preserve ongoing logging and SSH notification processing
