# Spec Delta

## MODIFIED Requirements

### Requirement: Local credential issuance and public server state

The administrator's computer SHALL generate and retain the OpenVPN CA private
key, VPN server keypairs and each device's OpenVPN or WireGuard keypair. OpenVPN
certificates SHALL be issued locally; routine CRLs SHALL be signed on the VPS.
CA issuance records and the device
enrollment/revocation records SHALL be authoritative local state with restrictive
permissions. This state SHALL be saved as owner-only Ansible Vault ciphertext for Git
storage, with the Vault password retained only on the controller, as specified in
[recovery-and-verification](../recovery-and-verification/spec.md).
Client profiles SHALL be assembled locally for transfer to devices.
The OpenVPN CA private key SHALL additionally be provisioned to the VPS through
the protected server-secret path solely for autonomous CRL signing. This is an
explicit exception to controller-only private authority storage; the full local
authority file SHALL NOT be deployed. Client private keys and the Vault password
SHALL remain on the controller and SHALL NOT be sent to the VPS.

For client enrollment, the VPS SHALL receive only public verification and access
data: WireGuard public keys and assigned addresses, and OpenVPN CA certificate,
signed certificates as needed, and the public issuance/revocation data needed
to generate CRLs. The CA signing key SHALL travel separately as a server secret,
never in the public membership release. Its persistent
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
- **AND** only the separately provisioned CA signing key is allowed on the VPS; client private keys, the full authority file and the Vault password remain off it

#### Scenario: Manage membership from the administrator's computer
- **WHEN** a local Make command adds or revokes a device over authenticated SSH
- **THEN** it updates the authoritative local Vault records and the corresponding public persistent and live access state on the VPS
- **AND** no private key is included in the public membership update

#### Scenario: Enroll an OpenVPN device
- **WHEN** the administrator adds an OpenVPN device
- **THEN** its keypair and signed certificate are created locally and its private key stays off the VPS
- **AND** OpenVPN verifies client certificates using the public CA certificate and has no access to the private CA key held by the renewal service

#### Scenario: Reapply or restore configuration
- **WHEN** the server's Ansible configuration is reapplied or a supported configuration restore is performed
- **THEN** the current deployed membership and revocation state remains effective
- **AND** an older playbook or inventory revision does not restore old membership

### Requirement: Authenticated and consistent mutations

Controller-initiated privileged changes SHALL use authenticated SSH as `admin` with host-key
verification and elevate to `root` through `su` authenticated with the `root`
password, following [server-administration](../server-administration/spec.md).
The server renewal service SHALL run locally with only the privileges needed
for signing and activation, without SSH, `su` credentials or a controller session.
Management commands SHALL report success only after authoritative local records, their
Ansible Vault ciphertext, and both persistent and live server access state are
updated and verified, and SHALL
clearly report partial failure. Shared mutable state SHALL use atomic updates
and a simple lock. Server state SHALL be derived from local enrollment/revocation
records; competing sources of truth SHALL NOT be maintained. Server-generated
CRLs and their sequence/expiry state SHALL be persistent derived server state;
routine renewal SHALL NOT require rewriting controller Vault files. An older
controller CRL or release SHALL NOT roll back a newer server CRL or revocations.
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

### Requirement: Effective OpenVPN revocation

OpenVPN revocation SHALL update local issuance/revocation records, sign an updated
CRL on the server from those updated records, activate it and promptly terminate
existing access. A CRL update alone
SHALL NOT be presented as immediate disconnection.
After deploying the updated CRL, the implementation SHALL briefly restart OpenVPN
to terminate existing sessions. The owner accepts interruption of all OpenVPN
clients during this restart. Success SHALL require verification that the service
is running again and the revoked client cannot reconnect. CRL readability,
validity, expiry and missing-file behavior SHALL be verified; a `crl-verify`
setting alone is not evidence of fail-closed behavior.

#### Scenario: Revoke an active client
- **WHEN** OpenVPN revocation reports success
- **THEN** the revoked certificate cannot establish a new connection
- **AND** existing sessions have been terminated by a brief OpenVPN restart
- **AND** non-revoked clients can reconnect after the restart

#### Scenario: Unusable CRL
- **WHEN** a CRL is missing, unreadable, invalid or expired during verification
- **THEN** the observed admission behavior is checked and documented
- **AND** readiness is not claimed if revoked credentials can regain access

### Requirement: Renew OpenVPN revocation information

The VPS SHALL automatically check CRL expiry, sign and activate a renewed
OpenVPN CRL before expiry with a documented safety window for retries. Routine
renewal SHALL require neither controller connectivity nor an operator command,
interactive login, unlock or password prompt. The protected server CA key and
latest successfully deployed issuance/revocation records SHALL be sufficient.
Renewal SHALL preserve CA, server and client identities, profile pins and all
current revocations. The server SHALL NOT invent enrollment or revocation changes.

A scheduled check outside the renewal window SHALL leave a valid, synchronized
CRL unchanged. After missed runs or VPS restart the server SHALL catch up. A manual
server renewal action SHALL remain available for diagnosis and recovery,
including after expiry; it SHALL NOT be the routine maintenance requirement.
Documentation SHALL describe the schedule, renewal window and status checks.

#### Scenario: Automatically renew an expiring CRL
- **WHEN** the controller is offline and a scheduled server check finds that the deployed CRL has entered the renewal window
- **THEN** the VPS signs, persists and activates a new valid CRL without operator input before expiry
- **AND** the CRL is verified against the current deployed authoritative revocations
- **AND** device and server identities and profile pins remain unchanged

#### Scenario: No renewal is due
- **WHEN** the deployed CRL is valid, synchronized and outside the renewal window
- **THEN** the scheduled check changes neither membership nor the active CRL and does not restart VPN services

#### Scenario: Resume after missed runs
- **WHEN** the VPS starts after missing scheduled checks, including past CRL expiry
- **THEN** it attempts overdue renewal from protected persistent signing material and current deployed records without contacting the controller
- **AND** it activates VPN listeners only after the required CRL validity checks pass
- **AND** expired revocation information is never treated as valid to bypass admission checks

### Requirement: Serialize and verify unattended CRL publication

Automatic server renewal SHALL serialize with membership publication, revocation
and state activation through shared synchronization and atomic persistence.
The service SHALL keep its signing key protected and SHALL NOT put secrets in
command arguments, logs, Git plaintext or public releases. Missing signing
material or invalid/untrusted revocation input SHALL cause a bounded, reported
failure without interactive prompts or admission-check bypasses.

Success SHALL require verification of the activated CRL, signature, validity,
revocations and service readiness. The server SHALL retain its latest CRL and
sequence state across reboot and Ansible reapplication. Each newly signed CRL
SHALL advance the sequence; retrying activation of the same signed CRL SHALL
retain it. Timer renewal and remote
membership updates SHALL NOT overwrite each other's state, discard a revocation,
reuse an older CRL sequence or bypass a pending server-key transition. A stale
membership publication SHALL be rejected; a current membership update SHALL be
reconciled with server CRL state rather than replace it with an older controller
CRL. Signing/activation failure SHALL retain safe state for automatic retry.

#### Scenario: Retry failed publication
- **WHEN** server-side signing succeeds but activation fails
- **THEN** the run reports partial failure and retains the signed result for automatic retry
- **AND** a subsequent attempt revalidates that result against the latest records before activation, re-signing only if its inputs or validity changed

#### Scenario: Concurrent or unfinished lifecycle operation
- **WHEN** renewal overlaps a membership publication or revocation, or encounters a pending server-key transition
- **THEN** shared synchronization prevents lost updates and revocations
- **AND** blocked renewal is reported without claiming successful activation or bypassing the transition

#### Scenario: Unattended credentials are unavailable
- **WHEN** the server cannot read its protected CA key or validate the deployed revocation records
- **THEN** it fails without a prompt, secret disclosure or unsafe replacement of the active CRL

#### Scenario: Controller publishes after autonomous renewal
- **WHEN** the controller submits a membership update after the server has renewed its CRL
- **THEN** activation preserves all current revocations and uses a valid CRL for the accepted membership state with a nondecreasing sequence
- **AND** an older controller CRL is not installed over the newer server result

#### Scenario: Reboot or reapply after renewal
- **WHEN** the VPS reboots or Ansible reapplies unchanged configuration after autonomous renewal
- **THEN** the latest committed CRL and revocation state remain effective and the timer remains enabled

### Requirement: Report automatic CRL renewal failures

The system SHALL retain the last verified publication result and deployed CRL
expiry, and notify the administrator of failed or blocked renewal with the
remaining validity and an actionable reason. An expired CRL SHALL be reported
as an error; missing or expired revocation information SHALL NOT be accepted as
valid merely to keep VPN listeners running. Notification failure SHALL itself
remain visible in local status/logs and SHALL NOT prevent subsequent renewal
attempts. Messages and status SHALL exclude secrets.

#### Scenario: Renewal cannot complete
- **WHEN** signing, persistence, publication or verification fails or is blocked
- **THEN** the administrator is notified of the failure and known remaining deployed CRL validity, or explicitly unknown validity
- **AND** status retains the failure until a verified successful publication supersedes it

#### Scenario: Notification delivery fails
- **WHEN** renewal fails and the failure notification cannot be delivered
- **THEN** both failures remain visible locally and later scheduled renewal attempts still run
