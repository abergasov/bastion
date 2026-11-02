# Design

## Context

See proposal.md. The current VPS signer owns a CA-key projection, systemd
timer/service and derived CRL sequence state. The local authority already owns
the CA database: `initial()` creates the CA with `-days 3650`, while
`revoke_open` uses `openssl ca -revoke` and `-gencrl`, retaining `index.txt` and
`crlnumber`. Its current `default_crl_days=30` is not the target behavior.

## Goals / Non-Goals

**Goals:**

- Restore controller-only CA custody and a long-lived, valid CRL.
- Preserve revocations, atomicity, locking and fail-closed publication checks.
- Migrate any VPS-derived sequence without decreasing it.

**Non-Goals:**

- No timer, notification replacement, persistent migration flag, new framework
  or live rollout.
- No indefinite certificates or claim that cleanup erases prior CA exposure.

## Decisions

- Local issuance sets CRL `nextUpdate` explicitly to
  `min(now + 3650 days, CA notAfter)`. `default_crl_days=3650` alone is rejected
  because it may outlive the CA. Certificates retain their existing finite
  lifetime.
- A local revoke uses the existing CA database and lock, so the next signed CRL
  contains every previously recorded revocation plus the new one. It validates
  signature, expiry and nondecreasing sequence before atomically publishing and
  activating the release.
- `make vpn-migrate-open VPN_HOST=<host>` is the one-time controller command.
  It reads the verified public current VPS release through the existing
  authenticated publish/reconcile path. If its sequence exceeds controller state,
  it seeds the controller sequence before signing, publishing and activating the
  local CRL; missing or unverifiable state fails closed. It changes no membership,
  and add/revoke do not invoke it. It runs before removing the CA-key projection,
  signer units and VPS sequence state. No scheduler, persistent migration switch
  or new framework is introduced.
- Reapply removes old signer resources idempotently only after the valid local
  CRL is active. This reduces future exposure but cannot revoke a prior copy of
  a CA key. Compromise recovery requires CA rotation only where earlier VPS
  exposure occurred.
- The root `CRL-RENEWAL-SILENT-FAILURES.md` reports a signer-only failure mode.
  It is removed as resolved by removing that signer, rather than keeping or
  extending its notification mechanism.

## Risks / Trade-offs

- [Bad VPS sequence input] → verify its public release and fail closed before
  seeding; do not overwrite with a lower sequence.
- [Controller clock or CA expiry] → calculate explicit bounded `nextUpdate` and
  reject unusable results before publication.
- [Interrupted cleanup] → retain the active local CRL and make reapply remove
  remaining obsolete resources; do not declare historical exposure erased.

## Migration Plan

1. Implement and test local bounded CRL issuance, full-set revocation and
   sequence migration with synthetic material.
2. On a real authorized transition, run `make vpn-migrate-open VPN_HOST=<host>`
   to verify the current public release, seed a higher sequence when necessary,
   sign/publish/activate the local CRL without membership change, then remove CA
   projection and signer units.
3. Reapply verifies the controller-only steady state. Live migration remains
   unrun until separately authorized.
