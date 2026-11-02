# Spec Delta

## MODIFIED Requirements

### Requirement: Local credential issuance and public server state

The administrator's computer SHALL generate and retain the OpenVPN CA private
key, VPN server keypairs and each device's OpenVPN or WireGuard keypair. OpenVPN
certificates and CRLs SHALL be issued and signed only on that computer. CA
issuance records and device enrollment/revocation records SHALL be authoritative
local state with restrictive permissions. This state SHALL be saved as owner-only
Ansible Vault ciphertext for Git storage, with the Vault password retained only
on the controller. Client profiles SHALL be assembled locally for transfer to
devices. Neither the CA private key nor a CA-key projection SHALL be deployed to
the VPS; client private keys, the full authority file and the Vault password
also remain off it.

For client enrollment, the VPS SHALL receive only public verification and access
data: WireGuard public keys and assigned addresses, and OpenVPN CA certificate,
signed certificates as needed and the signed CRL. Its persistent runtime files
SHALL be the deployed representation of local enrollment/revocation records,
separate from Git-tracked playbooks, inventory and templates. Ansible SHALL
configure services/networking without a competing membership list and SHALL NOT
overwrite current access state on a rerun.

The VPS still requires its own VPN server private keys. These SHALL be
provisioned separately through controller-side Vault. Administrative access to
deployed state SHALL require root privileges; services SHALL receive only the
file access necessary for their operation.

#### Scenario: Preserve owner-only authority
- **WHEN** a lifecycle command persists changed authority state
- **THEN** it saves owner-only Vault ciphertext before reporting success
- **AND** the VPS receives no CA private key, CA-key projection, client private key, full authority file or Vault password

#### Scenario: Manage membership from the administrator's computer
- **WHEN** a local Make command adds or revokes a device over authenticated SSH
- **THEN** it updates the authoritative local Vault records and the corresponding public persistent and live access state on the VPS
- **AND** no private key is included in the public membership update

#### Scenario: Enroll an OpenVPN device
- **WHEN** the administrator adds an OpenVPN device
- **THEN** its keypair and signed certificate are created locally and its private key stays off the VPS
- **AND** OpenVPN verifies client certificates using the public CA certificate without access to the CA private key

#### Scenario: Reapply or restore configuration
- **WHEN** the server's Ansible configuration is reapplied or a supported configuration restore is performed
- **THEN** the current deployed membership and revocation state remains effective
- **AND** an older playbook or inventory revision does not restore old membership

### Requirement: Authenticated and consistent mutations

Controller-initiated privileged changes SHALL use authenticated SSH as `admin`
with host-key verification and elevate to `root` through `su` authenticated with
the `root` password. Management commands SHALL report success only after
authoritative local records, their Ansible Vault ciphertext, and both persistent
and live server access state are updated and verified, and SHALL clearly report
partial failure. Shared mutable state SHALL use atomic updates and a simple lock.
Server state SHALL be derived from local enrollment/revocation records; competing
sources of truth SHALL NOT be maintained. The controller SHALL preserve CRL
sequence state and reject a rollback. Lifecycle and recovery mutations SHALL
atomically update the affected Vault ciphertext. Passwords, tokens, private keys
and Vault passwords SHALL NOT be supplied in Make arguments.

#### Scenario: Vault update failure
- **WHEN** a lifecycle operation cannot atomically save updated Vault ciphertext
- **THEN** it reports partial failure and does not report the mutation successful

#### Scenario: One part of a change fails
- **WHEN** a command updates local records or server state but cannot complete or verify the other required updates
- **THEN** it reports partial failure rather than success

#### Scenario: Concurrent changes
- **WHEN** two commands mutate the same membership state
- **THEN** locking and atomic updates prevent lost updates or partially written state

### Requirement: Effective OpenVPN revocation

OpenVPN revocation SHALL update local issuance/revocation records, preserve the
complete prior revocation set, locally sign a replacement CRL, atomically publish
and activate it, and promptly terminate existing access. The initial and
replacement CRL `nextUpdate` SHALL be the earlier of issuance time plus 3650 days
and the CA certificate's `notAfter`; client and server certificates remain finite.
A CRL update alone SHALL NOT be presented as immediate disconnection. After
deploying the updated CRL, the implementation SHALL briefly restart OpenVPN to
terminate existing sessions. Success SHALL require verification that the service
is running again and the revoked client cannot reconnect. CRL readability,
signature, validity, expiry, sequence/rollback and missing-file behavior SHALL
be verified; a `crl-verify` setting alone is not evidence of fail-closed behavior.

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

#### Scenario: Seed a server-generated sequence before signer removal
- **WHEN** a deployment replaces a VPS signer whose verified public current release has a newer CRL sequence than controller state
- **THEN** the controller seeds its sequence from that verified public release before locally signing and activating the replacement CRL
- **AND** it fails closed rather than publish a decreasing sequence

#### Scenario: Safe signer cleanup on reapply
- **WHEN** Ansible reapplies the controller-only CRL configuration
- **THEN** it first verifies a valid locally signed CRL is active and then removes obsolete CA-key projection, signer service, timer and server sequence state
- **AND** the removal does not claim to erase a CA key that may have been exposed previously

## REMOVED Requirements

### Requirement: Renew OpenVPN revocation information

**Reason**: A long-lived controller-issued CRL eliminates routine VPS signing.
**Migration**: Publish and activate the valid controller-issued CRL before
removing the VPS signer and its scheduling units.

### Requirement: Serialize and verify unattended CRL publication

**Reason**: The VPS renewal service and its generated CRL state are removed.
**Migration**: Retain controller-side locking, atomic publication, signature,
expiry, sequence and rollback validation for every local CRL publication.

### Requirement: Report automatic CRL renewal failures

**Reason**: There is no unattended VPS renewal operation to report.
**Migration**: Preserve ordinary lifecycle partial-failure reporting and
fail-closed validation; do not add a replacement notification system.
