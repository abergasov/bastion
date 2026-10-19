# Recovery and Verification Specification

## Purpose

Define recovery, secret protection and evidence required before declaring the VPN
server ready. No Nix evaluation, build or VM tests have been run for this baseline.

## Requirements

### Requirement: Recovery through server recreation

Bastion SHALL use server recreation as the recovery policy after failure. Tested
console/rescue access and an emergency root password SHALL NOT be prerequisites.
Preserving existing client access across server recreation is not required for
this personal service. CA and client secrets reside on the administrator's
computer, so VPS loss alone does not destroy them. Recovery SHALL support fresh issuance
and replacement client profiles using the recreated server's endpoint. Encrypted
server VPN keys may be retained through the recipient replacement procedure below;
these keys alone SHALL NOT be treated as a backup of CA or membership state.
Recreation SHALL preserve
the revocation invariant in
[device-lifecycle](../device-lifecycle/spec.md).

#### Scenario: Lose administrative access
- **WHEN** the server cannot be administered after a failure
- **THEN** the recovery procedure recreates it through the selected installation workflow
- **AND** it does not depend on a tested console or emergency root password
- **AND** fresh issuance does not require a backup of the previous VPN credentials
- **AND** previously revoked devices do not silently regain access

### Requirement: Persistent credential state and protected secrets

Local CA, client keys and enrollment/revocation records SHALL remain on the
administrator's computer across VPS lifecycle operations. Deployed public access
state and necessary VPN server secrets SHALL persist across ordinary reboots and
NixOS rebuilds. Additional backups of local credential state are optional;
recovery may use fresh issuance if that state is lost.
Server VPN keys SHALL use the encrypted repository storage defined below. If credential
backup/restore is supported, backups SHALL be encrypted and restores SHALL enforce
current revocations before exposing VPN listeners. Git and NixOS system generations
alone SHALL NOT count as a backup of runtime state. Real passwords, seeds, tokens,
private keys and client profiles SHALL NOT be exposed in Git, documentation, logs
or command arguments. Decrypted secrets SHALL NOT be interpolated into Nix
expressions or derivations. The provisioning and recovery policy for non-VPN
secrets, such as Telegram credentials, remains open.

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
- **AND** server VPN keys need not change solely because the age recipient changed
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
certificate SHALL be revoked locally, and client profiles/trust settings SHALL
be updated as needed to reject the old server identity. Local CA and client keys
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
public key-only SSH, fail2ban matching and ban/unban on IPv4/IPv6, device add/revoke
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

Readiness SHALL require real-client DNS/IPv6 checks on the supported operating
systems, a fresh SSH login, log rotation, service restart and actual reboot
notification checks. A successful build SHALL NOT be treated as proof of remote
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
