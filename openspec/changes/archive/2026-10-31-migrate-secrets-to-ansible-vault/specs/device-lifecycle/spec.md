# Spec Delta

## MODIFIED Requirements

### Requirement: Local credential issuance and public server state
The administrator's computer SHALL retain CA, client keys, issuance records and
authoritative enrollment/revocation records in owner-only Ansible Vault
ciphertext. The Vault password remains controller-only. The VPS SHALL receive
only public enrollment data plus the necessary server VPN private keys delivered
from controller-side Vault into protected persistent server storage; it SHALL
not receive CA/client private keys or any Vault password.

#### Scenario: Preserve owner-only authority
- **WHEN** a lifecycle command persists changed authority state
- **THEN** it saves owner-only Vault ciphertext before reporting success
- **AND** no authority private key or Vault password is sent to the VPS

#### Scenario: Manage membership from the administrator's computer
- **WHEN** a local lifecycle command changes membership
- **THEN** it updates owner Vault state and only corresponding public VPS state

#### Scenario: Enroll an OpenVPN device
- **WHEN** an OpenVPN device is enrolled
- **THEN** its private key and CA remain off the VPS

#### Scenario: Reapply or restore configuration
- **WHEN** configuration is reapplied or restored
- **THEN** current membership and revocations remain effective

### Requirement: Authenticated and consistent mutations
Lifecycle and recovery mutations SHALL atomically update the affected Vault
ciphertext and report partial failure if encrypted local state or server state
cannot be updated. Passwords, tokens, private keys and Vault passwords SHALL
NOT be supplied in Make arguments.

#### Scenario: Vault update failure
- **WHEN** a lifecycle operation cannot atomically save updated Vault ciphertext
- **THEN** it reports partial failure and does not report the mutation successful

#### Scenario: One part of a change fails
- **WHEN** either local Vault or server publication fails
- **THEN** the command reports partial failure

#### Scenario: Concurrent changes
- **WHEN** concurrent lifecycle mutations target the same state
- **THEN** locking and atomic writes prevent lost updates
