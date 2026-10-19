# Recovery and Verification Specification

## Purpose

Define recovery, secret protection and evidence required before declaring the VPN
server ready. No Nix evaluation, build or VM tests have been run for this baseline.

## Requirements

### Requirement: Recovery through server recreation

Bastion SHALL use server recreation as the recovery policy after failure. Tested
console/rescue access and an emergency root password SHALL NOT be prerequisites
for recovery. This does not remove the requirement to set the predefined `root`
and `admin` passwords during initial provisioning under
[server-administration](../server-administration/spec.md).
Preserving existing client access across server recreation is not required for
this personal service. CA and client secrets reside on the administrator's
computer, so VPS loss alone does not destroy them. Recovery SHALL support fresh issuance
and replacement client profiles using the recreated server's endpoint. Every
initial server creation and VPS recreation SHALL use a new OpenVPN server private
key and certificate generated on the administrator's computer. Recreation SHALL
NOT restore the previous OpenVPN server key or certificate. Routine reboots and
NixOS rebuilds SHALL preserve the current identity. A WireGuard server key may be
retained on ordinary VPS replacement through the recipient replacement procedure
below; these keys alone SHALL NOT be treated as a backup of CA or membership state.

After recreation, the administrator SHALL transfer replacement OpenVPN profiles
from their trusted computer to each device. Each profile SHALL pin only the new
certificate's SHA-256 fingerprint using `peer-fingerprint`. Old profiles SHALL be
removed or disabled on the devices, including automatic connection settings, and
existing sessions SHALL be disconnected before connecting with the new profile.
Recreating the VPS or revoking its certificate locally SHALL NOT be described as
automatically updating client trust: an unchanged profile still trusts its old
fingerprint. Recovery for a device SHALL require verifying that its new profile
connects to the replacement server and rejects the old server certificate.
Recreation SHALL preserve
the revocation invariant in
[device-lifecycle](../device-lifecycle/spec.md).

#### Scenario: Lose administrative access
- **WHEN** the server cannot be administered after a failure
- **THEN** the recovery procedure recreates it through the selected installation workflow
- **AND** it does not depend on a tested console or emergency root password
- **AND** fresh issuance does not require a backup of the previous VPN credentials
- **AND** previously revoked devices do not silently regain access

#### Scenario: Replace the OpenVPN server identity
- **WHEN** a VPS is recreated, whether after ordinary loss or compromise
- **THEN** a fresh OpenVPN server key and certificate are generated locally and the new certificate has a different SHA-256 fingerprint
- **AND** replacement device profiles contain only the new fingerprint
- **AND** after old profiles are removed or disabled and sessions disconnected, each updated device connects to the replacement and rejects the old certificate, even if the CA is unchanged

#### Scenario: Rebuild the existing server
- **WHEN** the existing VPS reboots or its NixOS configuration is rebuilt without server recreation
- **THEN** its OpenVPN key, certificate and fingerprint remain unchanged and existing profiles remain usable

### Requirement: Persistent credential state and protected secrets

Local CA, client keys and enrollment/revocation records SHALL remain on the
administrator's computer across VPS lifecycle operations. Deployed public access
state and necessary VPN server secrets SHALL persist across ordinary reboots and
NixOS rebuilds. Local credential state SHALL use the owner-only age-encrypted
repository storage defined below. Additional backups are optional; recovery may
use fresh issuance if that state and its usable encrypted copies are lost.
Server VPN keys SHALL use the encrypted repository storage defined below. If credential
backup/restore is supported, backups SHALL be encrypted and restores SHALL enforce
current revocations before exposing VPN listeners. Git and NixOS system generations
alone SHALL NOT count as a backup of runtime state. Real passwords, seeds, tokens,
private keys and client profiles SHALL NOT be exposed in Git, documentation, logs
or command arguments. Decrypted secrets SHALL NOT be interpolated into Nix
expressions or derivations. The provisioning and recovery policy for non-VPN
secrets, including the predefined account passwords and Telegram credentials,
remains open.

#### Scenario: Retain state on the existing server
- **WHEN** the server reboots or its NixOS configuration is rebuilt
- **THEN** current VPN credentials and revocations remain effective

#### Scenario: Restore an optional credential backup
- **WHEN** a supported credential restore procedure is tested
- **THEN** the restored server enforces current revocations before exposing VPN listeners

#### Scenario: Inspect secret exposure
- **WHEN** generated files, permissions, logs and Nix build artifacts are checked
- **THEN** plaintext secret material is absent from public artifacts and command arguments
- **AND** secret files have restrictive access permissions

### Requirement: Owner-only age encryption of local credential state

The OpenVPN CA private key, client private keys, CA issuance records and
authoritative device enrollment/revocation records SHALL be retained locally
and stored in Git only as age-encrypted files. Encryption SHALL use the owner's
public age recipient; neither the VPS recipient nor any identity available on
the VPS SHALL be able to decrypt this state. Server VPN keys SHALL continue to
use the separate SOPS/sops-nix scheme below.

The owner's private age key SHALL be stored in KeePassXC, outside the project
repository and off the VPS. Its protected backup SHALL remain recoverable
independently of the administrator's computer; it SHALL NOT depend solely on
files encrypted with that same age key. Decrypted working files SHALL remain
outside the repository with restrictive permissions and SHALL NOT enter logs,
command arguments or Nix build artifacts.

Management operations SHALL preserve updated local credential state in encrypted
form before reporting success. Committing and pushing ciphertext SHALL NOT be
required for each operation. Repository history SHALL NOT be treated as proof
that restored membership or revocation records are current; restores SHALL
enforce the revocation requirements in
[device-lifecycle](../device-lifecycle/spec.md).

#### Scenario: Store local credentials in the repository
- **WHEN** local credential state is prepared for storage in Git
- **THEN** CA and client private keys and issuance/enrollment/revocation records are encrypted to the owner with age
- **AND** the owner can decrypt them using the private age key kept in KeePassXC
- **AND** neither plaintext state nor the private age key is included in the repository
- **AND** the VPS identity cannot decrypt the files

#### Scenario: Persist an enrollment or revocation
- **WHEN** a management operation changes local credential state
- **THEN** success requires saving the updated age-encrypted state as well as the required server updates
- **AND** a failure to save encrypted state is reported as a partial failure, not success

#### Scenario: Restore encrypted local state
- **WHEN** credential state is recovered from repository ciphertext using the owner's age key
- **THEN** decryption is verified before the state is used
- **AND** an older repository revision does not silently reauthorize revoked devices

### Requirement: Encrypted server VPN keys in Git

The OpenVPN server private key and WireGuard server private key SHALL be stored
in Git only as SOPS ciphertext encrypted with age for two independent recipients:
the owner and the VPS. Each recipient SHALL be able to decrypt independently.
The owner's private age key and its protected backup SHALL remain off the VPS
and outside Git. The VPS SHALL hold its own private age key outside Git and
`/nix/store`; initial provisioning SHALL use authenticated access with host-key
verification. Public age recipients may be committed to Git.

sops-nix SHALL decrypt the VPN keys on the target host at activation into protected
runtime files under `/run/secrets`, with access limited to root and the services
that need them. Plaintext SHALL NOT enter Nix evaluation or build artifacts.
CA private keys, client private keys and authoritative enrollment/revocation
records SHALL remain on the administrator's computer. The VPS SHALL receive only
their public deployment data. Any encrypted copy of CA or client private keys
SHALL exclude the VPS from its recipients and SHALL NOT be decryptable using any
identity available on the VPS.

#### Scenario: Deploy encrypted server keys
- **WHEN** the server activates its configuration with its private age key available
- **THEN** sops-nix makes the VPN keys available in protected runtime files
- **AND** Git and Nix build artifacts contain only encrypted copies of those keys

#### Scenario: Inspect secret separation
- **WHEN** server files and all SOPS secrets decryptable by the VPS are inspected
- **THEN** they contain no CA private key or client private keys
- **AND** server VPN private keys remain available to their respective services

#### Scenario: Replace a lost VPS
- **WHEN** a replacement VPS has a new age key and the owner retains their private age key
- **THEN** the owner replaces the old VPS recipient with the verified new public recipient using `sops updatekeys` and commits the updated ciphertext
- **AND** the owner remains a recipient and the new VPS can decrypt without the old VPS private age key
- **AND** the newly generated OpenVPN server key is saved as SOPS ciphertext for the owner and replacement VPS before deployment
- **AND** the WireGuard server key may be retained if it was not exposed
- **AND** OpenVPN profiles are replaced and verified as required above; changing the age recipient alone is insufficient
- **AND** missing CA or membership state still requires fresh issuance and enrollment

### Requirement: Recovery after host compromise

Documentation SHALL state that encrypted repository storage does not protect
secrets from root access on the running VPS: an attacker can use its age identity,
read server secrets, change WireGuard membership or replace OpenVPN verification
rules. With only VPS access, the attacker SHALL have no access to the locally held
CA or client private keys and cannot sign certificates with that CA. This
separation SHALL NOT be represented as preventing arbitrary connections on a
root-compromised server.

Recovery from a confirmed full host compromise SHALL recreate the VPS, replace
its age identity and rotate exposed server VPN keys. The exposed OpenVPN server
certificate SHALL be revoked locally, and client profiles SHALL be replaced with
profiles pinning only the new certificate as required above. Local CA and client keys
need replacement if exposed; VPS compromise alone does not imply their exposure.
Other secrets accessible to the compromised host SHALL also be rotated.
Removing an age recipient SHALL NOT be
treated as revoking access to historical ciphertext or already obtained secrets.

#### Scenario: Replace a compromised VPS
- **WHEN** recovery follows a confirmed full host compromise
- **THEN** the replacement uses a new age identity and fresh server VPN keys
- **AND** recovery updates client trust so the compromised server identity is no longer accepted
- **AND** replacing recipients alone is not reported as sufficient recovery

### Requirement: Build and integration verification

Once implemented, Bastion SHALL run relevant formatting/static checks,
`nix flake check` and a build of the selected host's system closure. Focused NixOS
integration tests SHALL cover both tunnels, permitted and blocked forwarding,
public key-only SSH restricted to `admin`, rejection of direct root SSH login,
initial `admin`/`root` password setup, switching from `admin` to `root` through
`su` with the root password, fail2ban matching and ban/unban on IPv4/IPv6, device add/revoke
across reboot/rebuild, secret permissions and notifications using a local mock
endpoint. Recreation and supported rollback/restore procedures SHALL be tested,
including missing/expired CRLs, active-client revocation, local-only issuance and
export, recipient separation, and partial failure between local and server updates.

#### Scenario: Validate an implementation
- **WHEN** an implementation is submitted for readiness review
- **THEN** build, static and integration results are reported for the affected behavior
- **AND** revoked devices remain denied across the tested lifecycle operations
- **AND** unrun checks and known exclusions are explicitly reported

### Requirement: Real-client and live-operation verification

Readiness SHALL require real-client IPv4/IPv6 routing and DNS checks for both VPNs
on every supported operating system, including kill-switch enforcement during
tunnel loss, reconnection and client network changes, and restored access through
the VPS after reconnection. It SHALL also require a fresh SSH login, log rotation,
service restart and actual reboot
notification checks. On each supported OS, OpenVPN checks SHALL verify acceptance
of the current pinned server certificate and rejection of the old certificate
after recreation, including when both certificates share the same CA.
A successful build SHALL NOT be treated as proof of remote
reachability or client leak prevention.

#### Scenario: Build passes but client checks are absent
- **WHEN** the system builds successfully without the required client and live-operation checks
- **THEN** readiness is not declared
- **AND** the remaining checks are identified

### Requirement: Safe rollout within authorized scope

Changes to SSH, firewall, routing or credentials SHALL preserve a working
administrative session during rollout. Documentation-only work SHALL NOT deploy,
delete or alter a live server or send real Telegram messages without authorization.

#### Scenario: Apply an authorized access change
- **WHEN** an authorized rollout modifies administrative access or networking
- **THEN** a working administrative session is preserved while fresh connectivity is checked
- **AND** the agreed fallback after access loss is server recreation

#### Scenario: Migrate documentation
- **WHEN** requirements are reorganized into OpenSpec
- **THEN** only local documentation and OpenSpec configuration are changed
- **AND** no live server or Telegram endpoint is contacted for testing
