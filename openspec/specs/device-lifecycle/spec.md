# Device Lifecycle Specification

> Vault migration note: earlier age/SOPS/recipient wording is historical only.
> Current authority and server-key persistence use controller-only Ansible Vault.

## Purpose

Define the local management interface and safe credential lifecycle for individual
WireGuard and OpenVPN devices. These commands are specified but do not exist yet.

## Requirements

### Requirement: Single-server Make interface

The administrator SHALL manage devices from their own computer through a thin
Makefile entry point to existing tools and focused scripts. The SSH destination
SHALL come from `VPN_HOST` in the Makefile, without requiring a routine `HOST` or
`VPN` argument. A second management interface or multi-host selection framework
SHALL NOT be introduced without a concrete requirement.

The interface SHALL provide these targets:

| Operation | WireGuard | OpenVPN | Input |
| --- | --- | --- | --- |
| Add | `vpn-add-wg` | `vpn-add-open` | `CLIENT=<name>` |
| List | `vpn-list-wg` | `vpn-list-open` | No client argument |
| Export | `vpn-export-wg` | `vpn-export-open` | `CLIENT=<name>` |
| Revoke | `vpn-revoke-wg` | `vpn-revoke-open` | Local interactive selection, no `CLIENT` argument |

#### Scenario: Add and list devices
- **WHEN** the administrator runs `make vpn-add-wg CLIENT=phone` or `make vpn-add-open CLIENT=laptop`
- **THEN** a separate device keypair is generated and retained on the administrator's computer
- **AND** only public enrollment data is deployed to `VPN_HOST` for the selected protocol
- **AND** that protocol's list target shows the device without requiring a client argument

#### Scenario: Export a selected device
- **WHEN** the administrator runs `make vpn-export-wg CLIENT=phone` or `make vpn-export-open CLIENT=laptop`
- **THEN** the selected protocol's profile is exported subject to the private-key retention policy
- **AND** neither a `HOST` nor a `VPN` argument is required

### Requirement: Interactive revocation

Revocation SHALL list the selected protocol's clients and prompt locally for an
exact client name. Unknown names SHALL be rejected. Empty input, EOF or
cancellation SHALL leave state unchanged. No noninteractive revocation mode SHALL
be added unless requested.

#### Scenario: Select a known device
- **WHEN** the administrator runs `make vpn-revoke-wg` or `make vpn-revoke-open` and enters an exact listed name
- **THEN** the selected device is revoked for that protocol

#### Scenario: Reject or cancel selection
- **WHEN** the input is unknown, empty, EOF or cancelled
- **THEN** no credential or live access state is changed

### Requirement: Validate inputs before mutation

Management commands SHALL validate device names, public keys, addresses, duplicates
and path inputs before changing state, and validate parameters before local shell
or SSH use. Existing private keys SHALL NOT be implicitly overwritten. Passwords,
tokens and private keys SHALL NOT be supplied in Make arguments.

#### Scenario: Reject invalid input or a duplicate
- **WHEN** an operation contains an invalid parameter, unsafe path or conflicting identity
- **THEN** the operation fails before state mutation or unsafe shell/SSH use
- **AND** an existing private key remains unchanged

### Requirement: Local credential issuance and public server state

The administrator's computer SHALL generate and retain the OpenVPN CA private
key, VPN server keypairs and each device's OpenVPN or WireGuard keypair. OpenVPN
certificates and CRLs SHALL be issued and signed locally.
CA issuance records and the device
enrollment/revocation records SHALL be authoritative local state with restrictive
permissions. This state SHALL be saved as owner-only Ansible Vault ciphertext for Git
storage, with the Vault password retained only on the controller, as specified in
[recovery-and-verification](../recovery-and-verification/spec.md).
Client profiles SHALL be assembled locally for transfer to devices.
Neither the OpenVPN CA private key nor a CA-key projection SHALL be provisioned
to the VPS. The full local authority file, client private keys and Vault password
SHALL remain on the controller and SHALL NOT be sent to the VPS.

For client enrollment, the VPS SHALL receive only public verification and access
data: WireGuard public keys and assigned addresses, and OpenVPN CA certificate,
signed certificates as needed, and the signed CRL. Its persistent
runtime files SHALL be the deployed representation of local enrollment/revocation
records, separate from Git-tracked playbooks, inventory and templates. Ansible
SHALL configure services/networking without a competing membership list and
SHALL NOT overwrite current access state on a rerun.

The VPS still requires its own VPN server private keys. These SHALL be provisioned
separately through controller-side Vault and its Ansible-managed persistent/runtime integration as specified in
[recovery-and-verification](../recovery-and-verification/spec.md). Administrative
access to deployed state SHALL require root privileges; services SHALL receive only
the file access necessary for their operation.

#### Scenario: Preserve owner-only authority
- **WHEN** a lifecycle command persists changed authority state
- **THEN** it saves owner-only Vault ciphertext before reporting success
- **AND** the VPS receives no CA private key or CA-key projection; client private keys, the full authority file and the Vault password remain off it

#### Scenario: Manage membership from the administrator's computer
- **WHEN** a local Make command adds or revokes a device over authenticated SSH
- **THEN** it updates the authoritative local Vault records and the corresponding public persistent and live access state on the VPS
- **AND** no private key is included in the public membership update

#### Scenario: Enroll an OpenVPN device
- **WHEN** the administrator adds an OpenVPN device
- **THEN** its keypair and signed certificate are created locally and its private key stays off the VPS
- **AND** OpenVPN verifies client certificates using the public CA certificate and has no access to the CA private key

#### Scenario: Reapply or restore configuration
- **WHEN** the server's Ansible configuration is reapplied or a supported configuration restore is performed
- **THEN** the current deployed membership and revocation state remains effective
- **AND** an older playbook or inventory revision does not restore old membership

### Requirement: Authenticated and consistent mutations

Controller-initiated privileged changes SHALL use authenticated SSH as `admin` with host-key
verification and elevate to `root` through `su` authenticated with the `root`
password, following [server-administration](../server-administration/spec.md).
Management commands SHALL report success only after authoritative local records, their
Ansible Vault ciphertext, and both persistent and live server access state are
updated and verified, and SHALL
clearly report partial failure. Shared mutable state SHALL use atomic updates
and a simple lock. Server state SHALL be derived from local enrollment/revocation
records; competing sources of truth SHALL NOT be maintained. The controller SHALL
preserve CRL sequence state and reject rollback.
Lifecycle and
recovery mutations SHALL atomically update the affected Vault ciphertext.
Passwords, tokens, private keys and Vault passwords SHALL NOT be supplied in Make arguments.

#### Scenario: Vault update failure
- **WHEN** a lifecycle operation cannot atomically save updated Vault ciphertext
- **THEN** it reports partial failure and does not report the mutation successful

#### Scenario: One part of a change fails
- **WHEN** a command updates local records or server state but cannot complete or verify the other required updates
- **THEN** it reports partial failure rather than success

#### Scenario: Concurrent changes
- **WHEN** two commands mutate the same membership state
- **THEN** locking and atomic updates prevent lost updates or partially written state

### Requirement: Private profile handling

Client private keys SHALL be retained in protected local storage for re-export.
Exported profiles SHALL be private local files with restrictive permissions and
excluded from Git. Exports SHALL use local keys and SHALL NOT retrieve client
private keys from the VPS. A profile export SHALL NOT promise a private key
that is unavailable or silently replace it.
Deleting a downloaded profile SHALL NOT be represented as revocation.
OpenVPN exports SHALL include only the current locally issued server certificate's
SHA-256 fingerprint as `peer-fingerprint`, following
[vpn-connectivity](../vpn-connectivity/spec.md). If the current server certificate
is unavailable, export SHALL fail rather than omit the pin or reuse a stale one.

#### Scenario: Export after server recreation
- **WHEN** an authorized device's OpenVPN profile is exported after the replacement server's new certificate is issued
- **THEN** the profile contains only the new server certificate's fingerprint and the current endpoint
- **AND** no previous server fingerprint is retained as an alternative

#### Scenario: Current server certificate is unavailable
- **WHEN** an OpenVPN export cannot determine the current locally issued server certificate
- **THEN** export fails without producing an unpinned profile or one pinned to a stale certificate

#### Scenario: Local private key is missing
- **WHEN** an export requires a local private key that has been lost or removed
- **THEN** the command explains the limitation without silently replacing that key

#### Scenario: Delete a local profile
- **WHEN** the administrator deletes a downloaded profile
- **THEN** the device is not reported as revoked by that deletion

### Requirement: Effective WireGuard revocation

WireGuard revocation SHALL remove the peer from both the running interface and the
persistent source loaded after restart or Ansible reapplication.

#### Scenario: Revoke an active peer
- **WHEN** WireGuard revocation reports success
- **THEN** the device no longer has access through the running interface
- **AND** restarting or reapplying configuration does not restore the peer

### Requirement: Effective OpenVPN revocation

OpenVPN revocation SHALL update local issuance/revocation records, preserve the
complete prior revocation set, locally sign a replacement CRL, atomically publish
and activate it, and promptly terminate existing access. The initial and
replacement CRL `nextUpdate` SHALL be the earlier of issuance time plus 3650 days
and the CA certificate's `notAfter`; client and server certificates remain finite.
A CRL update alone
SHALL NOT be presented as immediate disconnection.
After deploying the updated CRL, the implementation SHALL briefly restart OpenVPN
to terminate existing sessions. The owner accepts interruption of all OpenVPN
clients during this restart. Success SHALL require verification that the service
is running again and the revoked client cannot reconnect. CRL readability,
signature, validity, expiry, sequence/rollback and missing-file behavior SHALL be verified; a `crl-verify`
setting alone is not evidence of fail-closed behavior.

Migration from a historical VPS signer SHALL use the explicit one-time
controller command `make vpn-migrate-open VPN_HOST=<host>`. It SHALL not add,
remove, revoke or otherwise change membership. Before signing, publishing and
activating the local CRL, it SHALL verify the public current VPS release and
seed a higher CRL sequence into controller state when necessary. Add and revoke
commands SHALL NOT perform this migration implicitly. No scheduler, persistent
migration flag or new framework SHALL be introduced.

#### Scenario: Revoke an active client
- **WHEN** OpenVPN revocation reports success
- **THEN** the locally signed CRL contains the new and all previously recorded revocations and is atomically active on the VPS
- **AND** the revoked certificate cannot establish a new connection
- **AND** existing sessions have been terminated by a brief OpenVPN restart
- **AND** non-revoked clients can reconnect after the restart

#### Scenario: Unusable CRL
- **WHEN** a CRL is missing, unreadable, invalid, expired or a sequence rollback during verification
- **THEN** the observed admission behavior is checked and documented
- **AND** readiness is not claimed if revoked credentials can regain access

#### Scenario: Migrate a historical VPS signer without membership change
- **WHEN** the administrator runs `make vpn-migrate-open VPN_HOST=<host>` for a historical VPS signer
- **THEN** the command verifies and seeds the server sequence before locally signing, publishing and activating the replacement CRL
- **AND** membership, device credentials and revocations remain unchanged
- **AND** invalid or lower remote sequence input fails closed

### Requirement: Revocations survive system lifecycle operations

A reboot, Ansible rerun, package update, configuration restore, backup restore or server recreation SHALL NOT
silently reauthorize revoked credentials. Restores SHALL reconcile current
revocations from authoritative local records before exposing VPN listeners.
Local records and deployed server runtime state SHALL remain independent of
playbook, inventory and package revisions. If current revocation state is unavailable, recovery
SHALL use fresh trust material rather than restore stale access grants.

#### Scenario: Restore older state
- **WHEN** a previous configuration revision or backup contains a formerly authorized device
- **THEN** current revocations are reconciled before VPN access is exposed
- **AND** that device remains denied
