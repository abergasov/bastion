# Recovery and Verification Specification

## Purpose

Define recovery, secret protection and evidence required before declaring the VPN
server ready. Ubuntu/Ansible provisioning and integration checks have not run;
historical NixOS results do not verify this baseline.

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
Ansible configuration reruns SHALL preserve the current identity. A WireGuard server key may be
retained on ordinary VPS replacement through the recipient replacement procedure
below; these keys alone SHALL NOT be treated as a backup of CA or membership state.

After recreation, Bastion SHALL make replacement OpenVPN profiles available from
the administrator's trusted computer. Each generated profile SHALL pin only the
new certificate's SHA-256 fingerprint using `peer-fingerprint`. Importing the
replacement profile, removing or disabling old profiles and automatic connection
entries, disconnecting old sessions and verifying server identity in the chosen
application are the user's responsibility. Recreating the VPS or revoking its
certificate locally SHALL NOT be described as automatically updating client
trust. Server readiness SHALL NOT require checks on each user's device.
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
- **AND** profile replacement and server identity checks in the chosen application are documented as user responsibilities

#### Scenario: Reapply configuration to the existing server
- **WHEN** the existing VPS reboots or its Ansible configuration is reapplied without server recreation
- **THEN** its OpenVPN key, certificate and fingerprint remain unchanged and existing profiles remain usable

### Requirement: Persistent credential state and protected secrets

Local CA, client keys and enrollment/revocation records SHALL remain on the
administrator's computer across VPS lifecycle operations. Deployed public access
state and necessary VPN server secrets SHALL persist across ordinary reboots and
Ansible configuration reruns. Local credential state SHALL use the owner-only age-encrypted
repository storage defined below. The encrypted repository hosted on GitHub is
the selected remote copy; no additional credential backup system is required.
Recovery may use fresh issuance if that state and its usable encrypted copies
are lost. Only committed and pushed state is available from GitHub.
Server VPN keys SHALL use the encrypted repository storage defined below. If credential
backup/restore is supported, backups SHALL be encrypted and restores SHALL enforce
current revocations before exposing VPN listeners. Git and configuration/package revisions
alone SHALL NOT count as a backup of runtime state. Real passwords, seeds, tokens,
private keys and client profiles SHALL NOT be exposed in Git, documentation, logs
or command arguments. Decrypted secrets SHALL NOT be stored in tracked Ansible inventory, playbooks,
templates, fact caches or task results. Secret-handling tasks SHALL suppress
secret output and diffs, including during failures and check mode. The predefined account-password material and the
complete ssh_notify configuration, including Telegram credentials, SHALL use
SOPS/age-encrypted Git storage with independent owner and VPS recipients, following
the same recipient protection and replacement procedure as server VPN keys.
The Ansible-managed SOPS integration SHALL supply protected runtime files for provisioning and service use;
initial deployment and recovery SHALL use the encrypted repository state.
Credentials exposed during a host compromise SHALL be rotated before reuse.

The owner authorizes reuse of needed secrets from the read-only local Ansible
project. Import SHALL decrypt only in protected local working storage outside
the repository and save required values in the agreed SOPS/age storage before
deployment. Vault passwords, seeds, unrelated secrets and administrator SSH
private keys SHALL NOT be copied to the VPS or committed as plaintext. Permission
to reuse secrets does not override fresh OpenVPN server identity requirements.

#### Scenario: Retain state on the existing server
- **WHEN** the server reboots or its Ansible configuration is reapplied
- **THEN** current VPN credentials and revocations remain effective

#### Scenario: Import approved source secrets
- **WHEN** implementation reuses needed secrets from `/home/alejandro/go/src/ansible`
- **THEN** the source is unchanged and only required values are transferred into the agreed encrypted storage
- **AND** decryption credentials and plaintext do not appear in Git, output, diffs, fact caches or command arguments
- **AND** the initial OpenVPN server identity is still generated freshly on the administrator's computer

#### Scenario: Restore an optional credential backup
- **WHEN** a supported credential restore procedure is tested
- **THEN** the restored server enforces current revocations before exposing VPN listeners

#### Scenario: Inspect secret exposure
- **WHEN** generated files, permissions, logs and automation artifacts are checked
- **THEN** plaintext secret material is absent from public artifacts and command arguments
- **AND** secret files have restrictive access permissions

### Requirement: Owner-only age encryption of local credential state

The OpenVPN CA private key, client private keys, CA issuance records and
authoritative device enrollment/revocation records SHALL be retained locally
and stored in Git only as age-encrypted files. Encryption SHALL use the owner's
public age recipient; neither the VPS recipient nor any identity available on
the VPS SHALL be able to decrypt this state. Server VPN keys SHALL continue to
use the separate SOPS/age scheme below.

The owner's private age key SHALL be stored in KeePassXC, outside the project
repository and off the VPS. No separate backup of this key SHALL be created as
part of Bastion. The owner accepts that losing the key makes owner-only encrypted
GitHub copies unusable if no decrypted local state remains. Recovery in that case
SHALL generate a new owner age identity and fresh VPN credentials, explicitly
re-enroll intended devices and replace their profiles; old credentials SHALL NOT
regain access. Decrypted working files SHALL remain
outside the repository with restrictive permissions and SHALL NOT enter logs,
command arguments or automation artifacts.

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

#### Scenario: Lose the owner key and local credential state
- **WHEN** the owner's age key and decrypted local credential state are lost while encrypted copies remain on GitHub
- **THEN** recovery does not claim that GitHub can restore the owner-only encrypted state
- **AND** a new owner age identity and fresh VPN credentials are generated, with explicit device enrollment and replacement profiles
- **AND** old credentials remain denied

### Requirement: Encrypted server VPN keys in Git

The OpenVPN server private key and WireGuard server private key SHALL be stored
in Git only as SOPS ciphertext encrypted with age for two independent recipients:
the owner and the VPS. Each recipient SHALL be able to decrypt independently.
The owner's private age key SHALL remain off the VPS
and outside Git. The VPS SHALL hold its own private age key outside Git and
public automation artifacts; initial provisioning SHALL use authenticated access with host-key
verification. Public age recipients may be committed to Git.

Ansible SHALL configure SOPS decryption on the target host before dependent
services start, including after every boot. Decrypted keys SHALL be protected
runtime files under `/run/secrets`, accessible only to root and the services that
need them. Decryption failure SHALL prevent dependent services from starting
with missing or stale secret files. Plaintext SHALL NOT enter public automation
artifacts, logs or diffs.
CA private keys, client private keys and authoritative enrollment/revocation
records SHALL remain on the administrator's computer. The VPS SHALL receive only
their public deployment data. Any encrypted copy of CA or client private keys
SHALL exclude the VPS from its recipients and SHALL NOT be decryptable using any
identity available on the VPS.

#### Scenario: Deploy encrypted server keys
- **WHEN** the server activates its configuration with its private age key available
- **THEN** the Ansible-managed SOPS integration makes the VPN keys available in protected runtime files
- **AND** Git and automation artifacts contain only encrypted copies of those keys

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
- **AND** replacement OpenVPN profiles are generated with the new fingerprint for users to install; changing the age recipient alone is insufficient
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
certificate SHALL be revoked locally, and replacement client profiles SHALL be generated
pinning only the new certificate as required above. Users are responsible for
installing them and updating trust in their applications. Local CA and client keys
need replacement if exposed; VPS compromise alone does not imply their exposure.
Other secrets accessible to the compromised host SHALL also be rotated.
Removing an age recipient SHALL NOT be
treated as revoking access to historical ciphertext or already obtained secrets.

#### Scenario: Replace a compromised VPS
- **WHEN** recovery follows a confirmed full host compromise
- **THEN** the replacement uses a new age identity and fresh server VPN keys
- **AND** recovery supplies profiles pinning only the new server certificate and identifies updating application trust as the user's responsibility
- **AND** replacing recipients alone is not reported as sufficient recovery

### Requirement: Automation and integration verification

Once implemented, Bastion SHALL run relevant formatting/static checks,
`ansible-playbook --syntax-check`, `ansible-lint` and isolated Ubuntu provisioning
tests. Tests SHALL verify initial application and idempotent reapplication with
unchanged inputs. Check mode alone SHALL NOT count as integration evidence.
Focused Ubuntu VM integration tests SHALL cover both tunnels, permitted and blocked forwarding,
public key-only SSH restricted to `admin`, rejection of direct root SSH login,
initial `admin`/`root` password setup, switching from `admin` to `root` through
`su` with the root password, fail2ban matching and ban/unban on IPv4/IPv6, device add/revoke
across reboot, package updates and Ansible reapplication, secret permissions and notifications using a local mock
endpoint. Recreation and supported configuration restore procedures SHALL be tested,
including missing/expired CRLs, active-client revocation, local-only issuance and
export, recipient separation, and partial failure between local and server updates.

#### Scenario: Validate an implementation
- **WHEN** an implementation is submitted for readiness review
- **THEN** syntax, lint, idempotence and integration results are reported for the affected behavior
- **AND** revoked devices remain denied across the tested lifecycle operations
- **AND** unrun checks and known exclusions are explicitly reported

### Requirement: Server connectivity and live-operation verification

Readiness SHALL require checks of both VPN endpoints using protocol-compatible
test peers, IPv4/IPv6 forwarding through the VPS, IPv6 preference and IPv4 fallback
with controlled test peers as specified in [vpn-connectivity](../vpn-connectivity/spec.md),
public DNS reachability through each tunnel and server-side peer isolation. It SHALL also require a fresh SSH
login, log rotation, service restart and actual reboot notification checks.
OpenVPN profile checks SHALL verify that exported fingerprints match the current
locally issued server certificate and are replaced after recreation. End-user
application selection, per-OS compatibility, kill switches, local-network
blocking and device-side routing, DNS failover and certificate verification are
outside Bastion acceptance criteria. A successful syntax check or Ansible run SHALL NOT be treated as
proof of remote reachability or client leak prevention.

#### Scenario: Automation passes but server connectivity checks are absent
- **WHEN** Ansible checks pass without the required server connectivity and live-operation checks
- **THEN** readiness is not declared
- **AND** the remaining server checks are identified

#### Scenario: End-user application checks are absent
- **WHEN** all required server, profile and lifecycle checks pass without testing end-user applications on each OS
- **THEN** the absent device checks do not block server readiness
- **AND** no claim is made that end-user devices prevent leaks or enforce certificate pinning

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
