# Device Lifecycle Specification

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
- **THEN** a separate device identity is added for the selected protocol on `VPN_HOST`
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

### Requirement: Authenticated and consistent mutations

Privileged changes SHALL use authenticated SSH with host-key verification and sudo.
Commands SHALL report success only after both persistent and live access state are
updated and verified, and SHALL clearly report partial failure. Shared mutable
state SHALL use atomic updates and a simple lock. The membership source of truth
and revocation-state ownership SHALL be defined before lifecycle implementation;
competing peer lists SHALL NOT be maintained.

#### Scenario: One part of a change fails
- **WHEN** a command updates persistent state but cannot update or verify live state, or vice versa
- **THEN** it reports partial failure rather than success

#### Scenario: Concurrent changes
- **WHEN** two commands mutate the same membership state
- **THEN** locking and atomic updates prevent lost updates or partially written state

### Requirement: Private profile handling

Exported profiles SHALL be private local files with restrictive permissions and
excluded from Git. A profile export SHALL NOT promise a private key that was never
retained. Key generation location and retention remain open design choices.
Deleting a downloaded profile SHALL NOT be represented as revocation.

#### Scenario: Private key was not retained
- **WHEN** an export would require a private key unavailable under the chosen retention policy
- **THEN** the command explains the limitation without silently replacing that key

#### Scenario: Delete a local profile
- **WHEN** the administrator deletes a downloaded profile
- **THEN** the device is not reported as revoked by that deletion

### Requirement: Effective WireGuard revocation

WireGuard revocation SHALL remove the peer from both the running interface and the
persistent source loaded after restart or rebuild.

#### Scenario: Revoke an active peer
- **WHEN** WireGuard revocation reports success
- **THEN** the device no longer has access through the running interface
- **AND** restarting or rebuilding does not restore the peer

### Requirement: Effective OpenVPN revocation

OpenVPN revocation SHALL deploy an effective CRL and promptly terminate existing
access. A CRL update alone SHALL NOT be presented as immediate disconnection.
The implementation SHALL test a local-only management mechanism or document an
agreed brief service restart. CRL readability, validity, expiry and missing-file
behavior SHALL be verified; a `crl-verify` setting alone is not evidence of
fail-closed behavior.

#### Scenario: Revoke an active client
- **WHEN** OpenVPN revocation reports success
- **THEN** the revoked certificate cannot establish a new connection
- **AND** existing access has been terminated through the selected mechanism

#### Scenario: Unusable CRL
- **WHEN** a CRL is missing, unreadable, invalid or expired during verification
- **THEN** the observed admission behavior is checked and documented
- **AND** readiness is not claimed if revoked credentials can regain access

### Requirement: Revocations survive system lifecycle operations

A reboot, NixOS rebuild, rollback, backup restore or server recreation SHALL NOT
silently reauthorize revoked credentials. Restores SHALL reconcile current
revocations before exposing VPN listeners. The storage layout remains an open
choice, subject to this invariant.

#### Scenario: Restore older state
- **WHEN** a previous system generation or backup contains a formerly authorized device
- **THEN** current revocations are reconciled before VPN access is exposed
- **AND** that device remains denied
