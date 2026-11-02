# Tasks

## 1. Contract and documentation

- [x] 1.1 Update affected baseline specs, OpenSpec notes, active change tasks and operator docs for the confirmed Vault decision; preserve archives and clearly record that no live deployment occurred.

## 2. Controller and runtime implementation

- [x] 2.1 Replace SOPS/age inputs, preflight and secret role with controller-side Ansible Vault loading and root-only persistent server files plus atomic `/run/secrets` activation; retain consumer paths and fail closed.
- [x] 2.2 Import only approved legacy Vault fields in protected temporary storage, write real Bastion Vault ciphertext containing password hashes and complete ssh_notify configuration, and prohibit Vault password/seed/CA/client data on the VPS.
- [x] 2.3 Migrate owner authority and server-key lifecycle/recovery ciphertext staging to Vault, preserve locking/partial-failure semantics and reapply validated VPN state after secret activation.

## 3. Verification

- [x] 3.1 Replace SOPS/age regression fixtures with Vault checks for input permissions, ciphertext, excluded values, no-log/no-diff delivery, reboot persistence and secret-exposure boundaries.
- [x] 3.2 Run focused tests, formatting, syntax, lint and relevant synthetic VM/recovery checks; update task evidence without claiming live VPS or Telegram verification.
