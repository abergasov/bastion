# Spec Delta

> **Superseded delta.** This CA-projection recovery delta records the 2026-11-01
> target and historical evidence only. `use-long-lived-controller-crl` replaces
> it; this file does not prescribe current baseline behavior.

## MODIFIED Requirements

### Requirement: Persistent credential state and protected secrets

Controller copies of the CA, client keys and enrollment/revocation records SHALL remain on the
administrator's computer across VPS lifecycle operations. Deployed public access
state and necessary VPN server secrets SHALL persist across ordinary reboots and
Ansible configuration reruns. Local credential state SHALL use the owner-only Ansible Vault encrypted
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
controller-side Ansible Vault encrypted Git storage. Vault password and ciphertext
SHALL not reach the VPS. The Ansible-managed persistent store SHALL atomically
supply protected runtime files for provisioning and service use;
initial deployment and recovery SHALL use the encrypted repository state.
Credentials exposed during a host compromise SHALL be rotated before reuse.

Ansible SHALL decrypt only on the controller and deliver only necessary server
files to root-owned persistent storage. Persistent server files and their runtime
projection SHALL have mode `0600`, with directories of mode `0700`. Boot activation
SHALL atomically replace `/run/secrets` from that store without controller
connectivity or a Vault password. Missing, invalid or stale material SHALL
prevent dependent services from using it. The Vault password and full decrypted
controller authority SHALL remain outside Git and SHALL NOT be copied to the VPS.
Client private keys, SSH seeds and unrelated Vault values SHALL NOT be delivered.
The CA signing key is the explicit exception: a separate protected server
projection SHALL supply it to the local CRL renewal service, never to OpenVPN
or the public release. The full authority ciphertext/database of private client
material SHALL remain controller-only. Public issuance/revocation records and
server-generated CRL sequence state SHALL persist separately from configuration.

The owner authorizes reuse of needed secrets from the read-only local Ansible
project. Import SHALL decrypt only in protected local working storage outside
the repository and save required values in the agreed Ansible Vault storage before
deployment. Vault passwords, seeds, unrelated secrets and administrator SSH
private keys SHALL NOT be copied to the VPS or committed as plaintext. Permission
to reuse secrets does not override fresh OpenVPN server identity requirements.

#### Scenario: Reboot without controller Vault access
- **WHEN** the VPS reboots after a successful controller-side deployment
- **THEN** protected runtime files are restored from its root-only persistent server store without a Vault password or Vault ciphertext on the VPS
- **AND** dependent services fail closed if required persistent material is absent

#### Scenario: Retain state on the existing server
- **WHEN** the server reboots or its Ansible configuration is reapplied
- **THEN** current VPN credentials and revocations remain effective without a Vault password on the VPS

#### Scenario: Import approved source secrets
- **WHEN** implementation reuses needed secrets from `/home/alejandro/go/src/ansible`
- **THEN** the source is unchanged and only required target values are read in protected temporary storage and saved as Bastion Vault ciphertext
- **AND** decryption credentials and plaintext do not appear in Git, output, diffs, fact caches or command arguments
- **AND** SSH seeds, client private state, the full authority file and Vault passwords are excluded from imported server values; only the separately selected CA signing key may be provisioned for server renewal
- **AND** the initial OpenVPN server identity is still generated freshly on the administrator's computer

#### Scenario: Restore an optional credential backup
- **WHEN** a supported credential restore procedure is tested
- **THEN** restoration uses controller-side Vault and the restored server enforces current revocations before exposing VPN listeners

#### Scenario: Inspect secret exposure
- **WHEN** generated files, permissions, logs and automation artifacts are checked
- **THEN** plaintext secret material is absent from public artifacts and command arguments
- **AND** secret files have restrictive access permissions
- **AND** the VPS contains neither the Vault password nor client private keys; only the renewal service and root can read the provisioned CA key

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
CA and client private keys and authoritative enrollment/revocation records
SHALL retain their controller copies. Under the current Vault model, the VPS
SHALL additionally receive the separately protected CA signing key and public
revocation projection for autonomous renewal. Client private keys and the full
local authority ciphertext SHALL NOT be delivered or decryptable by the VPS.

#### Scenario: Deploy encrypted server keys
- **WHEN** the server activates its configuration with its private age key available
- **THEN** the Ansible-managed SOPS integration makes the VPN keys available in protected runtime files
- **AND** Git and automation artifacts contain only encrypted copies of those keys

#### Scenario: Inspect secret separation
- **WHEN** server files and all SOPS secrets decryptable by the VPS are inspected
- **THEN** client private keys and the full authority file are absent, and the CA key is available only through the protected renewal-service projection
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

Documentation SHALL state that root access to the running VPS exposes the
server-side CA signing key as well as VPN server keys and other deployed secrets.
The CA key is not cryptographically limited to CRL renewal: a root attacker can
also sign certificates and forge CRLs. Client private keys and the Vault password
remain off the VPS; this does not make the exposed CA trustworthy.

Recovery from confirmed full host compromise SHALL recreate the VPS, replace
the exposed CA with fresh trust material, issue fresh server/device credentials
and require explicit re-enrollment of intended devices. Old CA trust and old
profiles SHALL NOT be reused. Replacement profiles SHALL pin only the newly
issued OpenVPN server certificate; users remain responsible for installing them
and removing old application trust. A path that preserves the exposed CA
SHALL NOT be reported as sufficient recovery after the server has received the
CA key.

Every other host-accessible secret SHALL also be rotated, including VPN server
keys, account-password material and notification credentials. Merely re-encrypting
or reusing Vault ciphertext SHALL NOT count as remediation. Recovery SHALL NOT
trust revocation or issuance state obtained from the compromised server; only
intended devices explicitly enrolled into fresh trust SHALL regain access.

#### Scenario: Replace a compromised VPS
- **WHEN** recovery follows a confirmed full compromise of a VPS provisioned with the CA signing key
- **THEN** controller-side Vault deployment supplies a fresh CA and fresh server keys and other required secrets without sending a Vault password or client private key
- **AND** intended devices are explicitly re-enrolled and receive replacement profiles pinning only the new server certificate
- **AND** updating application trust is documented as the user's responsibility
- **AND** host-accessible credentials are recorded as rotated before reuse
- **AND** preserving the old CA or merely re-encrypting existing ciphertext is rejected as insufficient recovery

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
including missing/expired CRLs, autonomous renewal with the controller offline,
active-client revocation, local certificate issuance and export, protected CA
projection without client-key exposure, compromise recovery with fresh CA trust,
and partial failure between local and server updates.

#### Scenario: Validate an implementation
- **WHEN** an implementation is submitted for readiness review
- **THEN** syntax, lint, idempotence and integration results are reported for the affected behavior
- **AND** revoked devices remain denied across the tested lifecycle operations
- **AND** unrun checks and known exclusions are explicitly reported
