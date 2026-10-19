# Server Administration Specification

## Purpose

Define publicly reachable, key-authenticated administration, account passwords,
privilege elevation and fail2ban protection for the future NixOS VPN server.

## Requirements

### Requirement: Public key-only SSH

SSH SHALL remain publicly reachable and accept public-key authentication only.
Only the `admin` account SHALL be permitted to log in over SSH. Direct SSH login
as `root` or any other account SHALL be rejected, including login using a valid
key. Password authentication SHALL be forbidden. Administration SHALL NOT require VPN
connectivity or a public source-IP allowlist. For inbound administrator access,
only the administrator's public key SHALL be placed on the server; the previous
Ansible private-key restoration pattern SHALL NOT be reproduced.
The installed `admin` account SHALL authorize the owner's existing Ed25519 public
key used for initial VPS access.

#### Scenario: Administer without a VPN
- **WHEN** an authorized administrator connects from a public address without a VPN
- **THEN** SSH permits login as `admin` with the authorized public key
- **AND** the source address does not need prior allowlisting

#### Scenario: Attempt password login
- **WHEN** a client attempts SSH authentication using a password
- **THEN** the server rejects that authentication method

#### Scenario: Reject SSH login as another account
- **WHEN** a client attempts SSH login as `root` or any account other than `admin`, even with a valid key
- **THEN** the server rejects the login

### Requirement: Initial account passwords and privilege elevation

Initial provisioning SHALL create the `admin` account and set the owner-supplied,
predefined passwords for both `admin` and `root`, following the existing Ansible
setup's account-password model. The administrator SHALL log in as `admin` using
an SSH key and switch to `root` using `su`, authenticated with the `root` password.
Setting account passwords SHALL NOT enable SSH password authentication.
The secret handling requirements in
[recovery-and-verification](../recovery-and-verification/spec.md) SHALL apply to
password provisioning; the concrete secret delivery mechanism remains to be selected.

#### Scenario: Provision account passwords
- **WHEN** initial server setup receives the predefined account passwords through the selected protected mechanism
- **THEN** it sets the supplied password for each of `admin` and `root`
- **AND** SSH continues to accept public-key authentication only

#### Scenario: Obtain root privileges as admin
- **WHEN** `admin` connects using an authorized SSH key and runs `su` to become `root`
- **THEN** the correct `root` password permits the switch to a root shell
- **AND** an incorrect root password does not authorize the switch

### Requirement: fail2ban protection for public SSH

Bastion SHALL run fail2ban for public SSH and verify actual SSH log matching and
ban/unban behavior on both IPv4 and IPv6. Bastion SHALL use the default SSH jail
policy supplied by the selected, pinned NixOS/nixpkgs revision and its fail2ban
package, without project-specific overrides to failure thresholds, observation
windows, ban durations, repeat-offender escalation or exemptions. Enabling SSH
protection and connecting it to the actual SSH logs and firewall SHALL remain
required. Implementation SHALL record and verify the effective defaults of the
selected revision rather than assume fixed numeric values.

#### Scenario: Enforce the default ban policy
- **WHEN** SSH failures from an IPv4 or IPv6 address meet the selected revision's default SSH jail policy
- **THEN** fail2ban detects the failures and enforces the default SSH ban
- **AND** ban removal is verified to restore access under the same policy
