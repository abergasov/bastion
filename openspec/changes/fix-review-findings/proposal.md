# Proposal

## Why

The owner authorized fixing four review findings: incomplete UFW conflict detection,
interrupted firewall applies that cannot resume, missing CRL renewal, and a stale
authority digest after successful device mutations.
The VPS-signing portion was superseded on 2026-11-02 by
`use-long-lived-controller-crl`; its recorded work is historical and does not
close the controller-only CRL requirements.

## What Changes

- Validate every UFW policy input before adopting an existing configuration.
- Allow safe retries of interrupted managed firewall updates without adopting unknown rules.
- Historical only: the former VPS-signer renewal, manual renewal and CA-key
  projection work is superseded by `use-long-lived-controller-crl`.
- Keep the current-authority digest synchronized with completed lifecycle mutations.
- Add focused regressions and verify the combined changes locally with synthetic inputs.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `device-lifecycle` and `recovery-and-verification`: superseded VPS-signer
  delta history; current requirements belong to `use-long-lived-controller-crl`.

The other fixes restore existing firewall, consistency and recovery requirements.

## Impact

Firewall role, lifecycle script, Make interface, server scheduling, protected CA projection, release/revocation synchronization,
compromise recovery, failure reporting, focused tests and operator docs.
No new dependencies or live deployment. Existing unrelated working-tree edits remain intact.
