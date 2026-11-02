# Tasks

## 1. Controller-issued CRL

- [x] 1.1 Change local CRL issuance to calculate explicit `nextUpdate = min(now + 3650 days, CA notAfter)` and verify a CRL never outlives its CA while certificates remain finite.
- [x] 1.2 Change OpenVPN revoke to retain the complete CA database revocation set, sign the replacement CRL locally, and verify the output includes old and new revocations.
- [x] 1.3 Preserve the existing lock, atomic publication/activation and fail-closed signature, expiry, sequence and rollback checks; verify partial failures do not replace a valid active CRL.

## 2. Safe signer removal

- [x] 2.1 Replace implicit add/revoke sequence migration with explicit one-time `make vpn-migrate-open VPN_HOST=<host>`; verify it changes no membership, seeds only from a verified public release, and fails closed on lower or unverifiable input. Evidence: `make --no-print-directory -n vpn-migrate-open VPN_HOST=vpn.example` and `ControllerCrlTest.test_migrate_crl_publishes_once_without_membership_mutation`.
- [x] 2.2 Publish and activate the locally signed CRL before removing the VPS CA-key projection, signer service/timer and server CRL sequence state; verify reapply is idempotent and does not claim historical CA exposure was erased.
- [x] 2.3 Remove signer-only CRL failure notification/status behavior and `CRL-RENEWAL-SILENT-FAILURES.md`; verify no routine VPS signing or scheduled renewal path remains.

## 3. Verification and documentation

- [x] 3.1 Add focused synthetic regressions for the explicit membership-preserving migration command, bounded expiry, repeated revocation, signature/expiry/rollback failures, cleanup and exposure-conditional recovery; verify they pass without real secrets or live access. Evidence: `python3 tests/crl-renewal-test.py` (7 tests) and `./tests/vpn-static-test.sh`.
- [x] 3.2 Update operator documentation and active-plan references for controller-only CRL custody, the explicit migration command and conditional CA rotation; verify no document presents add/revoke as migration or prescribes VPS signing, a CA-key projection or a renewal timer. Evidence: `docs/device-lifecycle.md` command list and migration section, `docs/maintenance.md` migration procedure, and `./tests/vpn-static-test.sh` target/Make invocation checks.
- [x] 3.3 Run focused tests, formatting/static checks and `rtk openspec validate --specs --strict --no-interactive` plus `rtk openspec validate --changes --strict --no-interactive`; record unrun disposable-VM and live migration checks.
  - Historical passed evidence: `python3 tests/crl-renewal-test.py`, `python3 tests/device-lifecycle-test.py`, `./tests/preflight-secrets-test.sh`, `./tests/runtime-secrets-activation-test.sh`, `./tests/secrets-static-test.sh`, `./tests/vpn-static-test.sh`, `python3 -m py_compile scripts/bastion-vpn-lifecycle tests/crl-renewal-test.py tests/device-lifecycle-test.py`, all three `ansible-playbook --syntax-check` commands, both strict OpenSpec validations, and `git diff --check`.
  - Unrun: disposable-VM checks and an authenticated live migration; neither live action is authorized by this change.
