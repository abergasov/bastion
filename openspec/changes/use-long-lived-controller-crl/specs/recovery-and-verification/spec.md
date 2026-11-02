# Spec Delta

## MODIFIED Requirements

### Requirement: Persistent credential state and protected secrets

Recovery may use fresh issuance if local state and its usable encrypted copies are lost. Real passwords, seeds, tokens, private keys and client profiles SHALL NOT be exposed in Git, documentation, logs or command arguments. Decrypted secrets SHALL NOT be stored in tracked Ansible inventory, playbooks, templates, fact caches or task results. Secret-handling tasks SHALL suppress secret output and diffs, including during failures and check mode. The Vault password and ciphertext SHALL not reach the VPS. Credentials exposed during a host compromise SHALL be rotated before reuse.

Ansible SHALL decrypt only on the controller and deliver only necessary server files to root-owned persistent storage. Persistent server files and their runtime projection SHALL have mode `0600`, with directories of mode `0700`. Missing, invalid or stale material SHALL prevent dependent services from using it. The Vault password, CA private key and full decrypted controller authority SHALL remain outside Git and SHALL NOT be copied to the VPS. Client private keys, SSH seeds and unrelated Vault values SHALL NOT be delivered. A signed CRL and public verification material may be delivered, but no CA-key projection, CRL signing service or timer SHALL be installed. Public enrollment/revocation data SHALL persist separately from configuration.

#### Scenario: Reboot without controller Vault access
- **WHEN** the VPS reboots after a successful controller-side deployment
- **THEN** protected runtime files are restored from its root-only persistent server store without a Vault password or Vault ciphertext on the VPS
- **AND** dependent services fail closed if required persistent material is absent

#### Scenario: Retain state on the existing server
- **WHEN** the server reboots or its Ansible configuration is reapplied
- **THEN** current VPN credentials and revocations remain effective without a Vault password or CA key on the VPS

#### Scenario: Import approved source secrets
- **WHEN** implementation reuses needed secrets from `/home/alejandro/go/src/ansible`
- **THEN** the source is unchanged and only required target values are read in protected temporary storage and saved as Bastion Vault ciphertext
- **AND** decryption credentials and plaintext do not appear in Git, output, diffs, fact caches or command arguments
- **AND** CA and client private state, SSH seeds, the full authority file and Vault passwords are excluded from imported server values

#### Scenario: Restore an optional credential backup
- **WHEN** a supported credential restore procedure is tested
- **THEN** restoration uses controller-side Vault and the restored server enforces current revocations before exposing VPN listeners

#### Scenario: Inspect secret exposure
- **WHEN** generated files, permissions, logs and automation artifacts are checked
- **THEN** plaintext secret material is absent from public artifacts and command arguments
- **AND** secret files have restrictive access permissions
- **AND** the VPS contains neither the Vault password, CA private key nor client private keys

### Requirement: Encrypted server VPN keys in Git

The OpenVPN server private key and WireGuard server private key SHALL be stored in Git only as SOPS ciphertext encrypted with age for two independent recipients: the owner and the VPS. Each recipient SHALL be able to decrypt independently. The owner's private age key SHALL remain off the VPS and outside Git. The VPS SHALL hold its own private age key outside Git and public automation artifacts.

Ansible SHALL configure SOPS decryption on the target host before dependent services start. Decrypted keys SHALL be protected runtime files under `/run/secrets`, accessible only to root and the services that need them. Decryption failure SHALL prevent dependent services from starting with missing or stale secret files. Plaintext SHALL NOT enter public automation artifacts, logs or diffs. CA and client private keys and authoritative enrollment/revocation records SHALL retain their controller copies and SHALL NOT be delivered or decryptable by the VPS.

#### Scenario: Deploy encrypted server keys
- **WHEN** the server activates its configuration with its private age key available
- **THEN** the Ansible-managed SOPS integration makes the VPN keys available in protected runtime files
- **AND** Git and automation artifacts contain only encrypted copies of those keys

#### Scenario: Inspect secret separation
- **WHEN** server files and all SOPS secrets decryptable by the VPS are inspected
- **THEN** the CA key, client private keys and full authority file are absent
- **AND** server VPN private keys remain available to their respective services

#### Scenario: Replace a lost VPS
- **WHEN** a replacement VPS has a new age key and the owner retains their private age key
- **THEN** the owner replaces the old VPS recipient with the verified new public recipient using `sops updatekeys` and commits the updated ciphertext
- **AND** the owner remains a recipient and the new VPS can decrypt without the old VPS private age key
- **AND** the newly generated OpenVPN server key is saved as SOPS ciphertext for the owner and replacement VPS before deployment
- **AND** the WireGuard server key may be retained if it was not exposed
- **AND** replacement OpenVPN profiles are generated with the new fingerprint for users to install
- **AND** missing CA or membership state still requires fresh issuance and enrollment

### Requirement: Recovery after host compromise

Documentation SHALL state that root access to the running VPS exposes VPN server keys and other deployed secrets. It does not expose the controller-only CA private key merely because the VPS was compromised; client private keys and the Vault password also remain off the VPS.

Recovery from confirmed full host compromise SHALL recreate the VPS and rotate every host-accessible secret, including VPN server keys, account-password material and notification credentials. Merely re-encrypting or reusing Vault ciphertext SHALL NOT count as remediation. Recovery SHALL NOT trust revocation or issuance state obtained from the compromised server. The controller CA and existing device trust MAY be retained only when there is no evidence that an earlier VPS CA-key projection exposed that CA. If such earlier exposure occurred, recovery SHALL replace the CA with fresh trust material, issue fresh server/device credentials and require explicit re-enrollment; old CA trust and old profiles SHALL NOT be reused.

#### Scenario: Replace a compromised VPS
- **WHEN** recovery follows a confirmed full compromise and the controller verifies that the CA was never projected to that VPS
- **THEN** controller-side Vault deployment supplies fresh server keys and other required secrets without sending a Vault password, CA key or client private key
- **AND** host-accessible credentials are recorded as rotated before reuse

#### Scenario: Replace a compromised VPS after earlier CA exposure
- **WHEN** recovery follows a confirmed full compromise of a VPS to which the CA key was previously projected
- **THEN** controller-side recovery supplies a fresh CA and fresh server keys without sending a Vault password or client private key
- **AND** intended devices are explicitly re-enrolled and receive replacement profiles pinning only the new server certificate
- **AND** preserving the exposed CA or merely re-encrypting existing ciphertext is rejected as sufficient recovery

### Requirement: Automation and integration verification

Once implemented, Bastion SHALL run relevant formatting/static checks, `ansible-playbook --syntax-check`, `ansible-lint` and isolated Ubuntu provisioning tests. Tests SHALL verify initial application and idempotent reapplication with unchanged inputs. Check mode alone SHALL NOT count as integration evidence. Focused Ubuntu VM integration tests SHALL cover both tunnels, permitted and blocked forwarding, device add/revoke across reboot, package updates and Ansible reapplication, secret permissions and notifications using a local mock endpoint. Recreation and supported configuration restore procedures SHALL be tested, including missing/expired CRLs, long-lived controller-issued CRL publication and revocation, signer cleanup on reapply, active-client revocation, local certificate issuance and export, no CA-key projection, exposure-conditional compromise recovery, and partial failure between local and server updates.

#### Scenario: Validate an implementation
- **WHEN** an implementation is submitted for readiness review
- **THEN** syntax, lint, idempotence and integration results are reported for the affected behavior
- **AND** revoked devices remain denied across the tested lifecycle operations
- **AND** unrun checks and known exclusions are explicitly reported
