# Spec Delta

## MODIFIED Requirements

### Requirement: Persistent credential state and protected secrets
Local CA, client keys and enrollment/revocation records SHALL remain on the
administrator's computer. Server secrets and owner-only local credential state
SHALL be stored in Git only as Ansible Vault ciphertext. The Vault password and
decrypted controller state SHALL remain on the administrator's computer and
outside Git; neither SHALL be copied to the VPS.

Ansible SHALL decrypt only on the controller and deliver only the necessary
server files into root-owned persistent storage on the VPS. Persistent server
files and a protected runtime projection SHALL be mode `0600`; their directory
SHALL be mode `0700`. A boot activation SHALL atomically replace `/run/secrets`
from that persistent store without a Vault password or controller connectivity.
Missing, invalid or stale material SHALL prevent dependent services from using
it. CA/client private keys, Vault password, SSH seed and unrelated Vault values
SHALL NOT be delivered. Secret output, diffs, tracked inventory/templates,
facts, logs and command arguments SHALL exclude plaintext.

#### Scenario: Reboot without controller Vault access
- **WHEN** the VPS reboots after a successful controller-side deployment
- **THEN** protected runtime files are restored from its root-only persistent
  server store without a Vault password or Vault ciphertext on the VPS
- **AND** dependent services fail closed if required persistent material is absent

#### Scenario: Import approved source secrets
- **WHEN** required values are imported from the approved read-only legacy Vault
- **THEN** only required target values are read in protected temporary storage
  and saved as Bastion Vault ciphertext
- **AND** seed, CA/client state, Vault password and plaintext do not enter Git,
  VPS storage, logs or command arguments

#### Scenario: Retain state on the existing server
- **WHEN** configuration is reapplied or the server reboots
- **THEN** required protected server state remains available without a Vault key

#### Scenario: Restore an optional credential backup
- **WHEN** a supported backup is restored
- **THEN** it uses controller-side Vault and preserves current revocations

#### Scenario: Inspect secret exposure
- **WHEN** controller and VPS secret locations are inspected
- **THEN** the VPS contains neither Vault password nor owner-only material

### Requirement: Recovery after host compromise
Recovery after host compromise SHALL recreate the VPS and rotate every server
secret that was accessible on that host, including account-password material and
notification credentials. It SHALL create a fresh OpenVPN server key and
certificate and replacement profiles as before. Re-encrypting or reusing an
existing Vault ciphertext alone SHALL NOT be described as remediation. Local
CA/client state is rotated only when locally exposed.

#### Scenario: Replace a compromised VPS
- **WHEN** recovery creates a replacement VPS after confirmed compromise
- **THEN** controller-side Vault deployment supplies fresh required server
  secrets and no Vault password or owner-only secret reaches the host
- **AND** recovery records that host-accessible credentials were rotated before
  reuse
