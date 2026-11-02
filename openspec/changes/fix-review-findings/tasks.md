# Tasks

## 1. Review fixes

- [x] 1.1 Reject unrecognized effective UFW policy inputs, including after rules and initialization hooks; prove fresh/known states pass and custom allowances/hooks fail before mutation using focused synthetic checks. Corrected package canonical sources and captured native logging scaffolds; synthetic guard fixtures and actual Ubuntu fresh apply passed (`/tmp/bastion-ufw-runtime.MedBTX/root-fresh-2.log`, exit 0).
- [x] 1.2 Implement autonomous server CRL generation/activation using current deployed revocation records and a protected CA key; reconcile lifecycle publication, immutable releases/manifests and CRL sequence state under the existing server lock. Reject stale membership and preserve newer revocations across retries/reapply. The manual controller action and its earlier tests remain historical partial evidence only.
- [x] 1.3 Refresh current-authority after successful final saves; test ordinary successful add/revoke operations and recovery eligibility without weakening stale-ciphertext rejection. Dedicated suite: 4 tests passed; existing lifecycle suite: 32 passed; final-save ordering reviewed.
- [x] 1.4 Make interrupted managed UFW configuration safely retryable; test partial template/rule/manifest states and reject unknown custom state. Seven focused tests passed. Actual Ubuntu recovery from partial template/rule writes and pending reload with matching files passed, including removal of stale IPv4/IPv6 kernel rules, manifest verification and marker cleanup (`root-pending.log`, exit 0).
- [x] 1.5 Provision the isolated server CA-key projection, install/enable a systemd timer and boot catch-up, add expiry/status/failure notifications, and adapt the manual action to the server renewal path. Document operation without controller connectivity; keep client keys, SSH private key and Vault password off the VPS.
- [ ] 1.6 Test automatic renewal with synthetic secrets: controller offline, due/no-op, expired-CRL boot, permissions/missing key, concurrent revoke, stale controller release, sequence persistence, activation retry and notification failure. Verify unchanged identities and revoked-client denial through timer execution, reboot and Ansible reapply on a disposable Ubuntu VM.
- [x] 1.7 Update compromise recovery to reject reuse of a server-exposed CA, create fresh trust and require explicit device re-enrollment/replacement profiles; add regression coverage and update operator guidance before marking readiness.

## 2. Combined verification

- [ ] 2.1 After implementing automatic renewal, run combined regressions, make test, relevant syntax/static checks and strict OpenSpec validation; review the combined diff and record exclusions. The earlier manual-renewal/UFW verification passed as recorded in design.md, but does not verify automation.
