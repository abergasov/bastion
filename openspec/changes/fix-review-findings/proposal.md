# Proposal

## Why

The owner authorized fixing four review findings: incomplete UFW conflict detection,
interrupted firewall applies that cannot resume, missing CRL renewal, and a stale
authority digest after successful device mutations.
The owner corrected the CRL requirement on 2026-11-01: renewal must run automatically on the VPS itself;
the implemented manual command alone does not close this finding.

## What Changes

- Validate every UFW policy input before adopting an existing configuration.
- Allow safe retries of interrupted managed firewall updates without adopting unknown rules.
- Provide automatic server-side CRL renewal and verified activation before expiry, with retries and failure notification, without replacing identities or losing revocations.
- Retain manual renewal for recovery; routine operation must not depend on weekly operator commands.
- Provision the CA signing key separately to the server while keeping client private keys and the Vault password local; require fresh CA trust after host compromise.
- Keep the current-authority digest synchronized with completed lifecycle mutations.
- Add focused regressions and verify the combined changes locally with synthetic inputs.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `device-lifecycle`: server-local CRL signing, protected CA projection, serialized publication, retries and visible failures.
- `recovery-and-verification`: CA-key exposure boundary and fresh-CA recovery after host compromise.

The other fixes restore existing firewall, consistency and recovery requirements.

## Impact

Firewall role, lifecycle script, Make interface, server scheduling, protected CA projection, release/revocation synchronization,
compromise recovery, failure reporting, focused tests and operator docs.
No new dependencies or live deployment. Existing unrelated working-tree edits remain intact.
