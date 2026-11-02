# Proposal

## Why

The 2026-11-01 decision allowed a CA-key projection and autonomous CRL signer
on the VPS. The owner now supersedes that exception: the OpenVPN CA is
controller-only and the VPS must not sign routine CRLs. A locally issued CRL
with an approximately ten-year lifetime removes the routine signer and its
timer, while retaining finite certificates and fail-closed CRL validation.

## What Changes

- Issue and sign OpenVPN CRLs only on the controller. Initial CRL `nextUpdate`
  is the earlier of now plus 3650 days and the CA certificate's `notAfter`.
- Make local revocation retain the complete previous revocation set, generate a
  replacement CRL, and atomically publish and activate it under the existing
  lifecycle locking and validation contract.
- Remove the VPS CA-key projection, routine signer, timer/service, server CRL
  sequence state and autonomous-renewal behavior safely on reapply. Removal is
  not a claim that an already exposed CA key was erased from historical access.
- Before signer removal, run explicit one-time `make vpn-migrate-open` to seed
  controller sequence state from the verified public current VPS release, then
  sign, publish and activate the local CRL without changing membership.
- Preserve signature, expiry, rollback and fail-closed checks; certificates
  remain finite. CA rotation is required only when an earlier VPS CA exposure
  occurred.
- Supersede the 2026-11-01 VPS-signer decision, its active-plan claims and the
  obsolete signer silent-failure note. No new notification mechanism is added.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `device-lifecycle`: controller-only CRL issuance, atomic local revocation
  publication, and removal of server-side signing.
- `recovery-and-verification`: CA-key non-projection, exposure-conditional
  compromise recovery, and focused verification of signer cleanup.

## Impact

The lifecycle script and tests, VPN/secrets Ansible roles and their tests,
operator documentation, active OpenSpec plans and the obsolete signer note are
affected. No dependency, deployment, live action, certificate-lifetime change
or client-key transfer is introduced.
