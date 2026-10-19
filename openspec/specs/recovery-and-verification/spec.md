# Recovery and Verification Specification

## Purpose

Define recovery, secret protection and evidence required before declaring the VPN
server ready. No Nix evaluation, build or VM tests have been run for this baseline.

## Requirements

### Requirement: Recovery through server recreation

Bastion SHALL use server recreation as the recovery policy after failure. Tested
console/rescue access and an emergency root password SHALL NOT be prerequisites.
Credential restoration versus fresh issuance and handling a changed endpoint IP
remain open. Recreation SHALL preserve the revocation invariant in
[device-lifecycle](../device-lifecycle/spec.md).

#### Scenario: Lose administrative access
- **WHEN** the server cannot be administered after a failure
- **THEN** the recovery procedure recreates it through the selected installation workflow
- **AND** it does not depend on a tested console or emergency root password
- **AND** previously revoked devices do not silently regain access

### Requirement: Recoverable credential state and protected secrets

PKI issuance records, current revocations and necessary server secrets SHALL be
recoverable through encrypted backups. Git and NixOS system generations alone
SHALL NOT count as a backup of runtime state. Real passwords, seeds, tokens,
private keys and client profiles SHALL NOT be exposed in Git, documentation, logs
or command arguments. Decrypted secrets SHALL NOT be interpolated into Nix
expressions or derivations. Backup destination and secret tooling remain open.

#### Scenario: Recover from backup
- **WHEN** a supported restore procedure is tested
- **THEN** required issuance records, revocations and server secrets are recoverable
- **AND** the restored server enforces current revocations before exposing VPN listeners

#### Scenario: Inspect secret exposure
- **WHEN** generated files, permissions, logs and Nix build artifacts are checked
- **THEN** secret material is absent from public artifacts and command arguments
- **AND** secret files have restrictive access permissions

### Requirement: Build and integration verification

Once implemented, Bastion SHALL run relevant formatting/static checks,
`nix flake check` and a build of the selected host's system closure. Focused NixOS
integration tests SHALL cover both tunnels, permitted and blocked forwarding,
public key-only SSH, fail2ban matching and ban/unban on IPv4/IPv6, device add/revoke
across reboot/rebuild, secret permissions and notifications using a local mock
endpoint. Recreation and supported rollback/restore procedures SHALL be tested,
including missing/expired CRLs and active-client revocation.

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
