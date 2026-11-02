# Design

> **Superseded CRL design.** Every VPS CA-key projection, signer, timer,
> server-generated CRL state and renewal-notification statement below records
> the 2026-11-01 design and its historical evidence only. It is superseded by
> `use-long-lived-controller-crl`; it does not prescribe current behavior.

## Context

See proposal.md. The owner requested one agent per finding. Two pairs share files:
UFW conflict detection/retry handling and lifecycle renewal/authority marker fixes.
The owner subsequently corrected the CRL requirement: renewal must be automatic
and run on the VPS itself, even with the controller offline.
The manual implementation and its tests below are partial evidence, not completion
of the revised requirement.

## Goals / Non-Goals

Complete the four fixes with focused regression evidence. No live rollout,
real-secret access, Telegram delivery, new dependency or general transaction framework.

## Decisions

- Use the existing UFW native file policy and reject unknown policy sources.
  Preserve strict conflict checks while allowing only demonstrably managed
  interrupted state to resume or restoring the previous configuration on failure.
- Renew CRLs on the VPS using a protected copy of the existing CA key and the
  latest deployed public issuance/revocation records. Keep controller authority,
  client keys and Vault password local; no second membership authority is created.
  The server owns generated CRLs and their sequence/expiry state. Preserve
  identities during routine renewal and replace CA trust after host compromise.
- Update the authority digest only after the final successful ciphertext save,
  retaining existing partial-failure tracking.
- Assign UFW preflight policy inspection to agent 1 and interrupted apply handling
  to agent 4. Agent 4 coordinates shared-file edits with agent 1.
  Agent 2 owns CRL renewal; agent 3 owns only final authority marker synchronization.
  Root owns this change's artifacts, integration checks and final diff review.

## Risks / Trade-offs

- Broader UFW inspection can reject customized hosts; report exact conflicts
  without deleting or accepting their rules.
- Retry handling must not treat arbitrary edited files as managed state.
- Root compromise now exposes the CA key and permits both certificate issuance
  and CRL forgery. The key is not restricted cryptographically to renewal.
  Mitigation is fresh CA trust, device re-enrollment and replacement profiles;
  a CA-preserving compromise-recovery path is insufficient.
- Concurrent timer and lifecycle publication can roll back revocations or CRL
  sequence state. Use the existing server state lock, versioned public input and
  atomic activation; do not overwrite a renewed server CRL from controller state.
- Shared-file edits require coordination and a combined regression run.

## Migration Plan

Implement and test with synthetic local inputs, then review the combined diff.
Any production apply remains separately authorized. Do not change existing live
readiness checkboxes or claim historical VM evidence covers these fixes.

## Server renewal implementation plan

The execution location and CA-key exception are the owner's confirmed decision.
The mechanism below is implemented. Synthetic regression coverage exists; the
pending task 1.6 retains the distinct disposable-VM timer, reboot and
revoked-client admission evidence, so this text makes no VM or live-readiness
claim.

Before this change, `scripts/bastion-vpn-lifecycle` signed locally
and included `crl.pem` in a public release; `bastion-vpn-publish-state` accepted an
exact archive schema and used `/run/lock/bastion-vpn-state.lock`.
`bastion-vpn-verify-state` checked the release manifest and CRL expiry;
`bastion-vpn-apply-state-once` activated that immutable release and restarted
OpenVPN. OpenVPN read `/run/bastion-vpn/active/openvpn/crl.pem`. Merely installing
a timer would have left controller publication able to replace its result.

- Add an Ansible-managed native systemd timer and a focused local renewal command
  on Ubuntu. Proposed defaults are daily checks, renewal with seven days left,
  and a 30-day CRL lifetime. Use persistent catch-up and run expiry reconciliation
  on boot before the existing validity gate starts VPN listeners. Bound failure
  duration and keep subsequent runs enabled; no controller schedule is needed.
- Provision only the CA key through the existing controller-decrypted Vault
  projection: root-owned persistent/runtime files, 0600 files and 0700 directories.
  Give OpenVPN no access to it. Do not copy the full authority, client keys,
  administrator SSH private key, Vault ciphertext or Vault password to the VPS.
- Extend public membership deployment with the issuance/revocation input needed
  for CRL generation, bound to CA identity and membership revision. Retain local
  enrollment/revocation authority; ordinary timer runs never change membership.
  Reject older revisions and accept repeated current revisions idempotently.
- Keep the existing immutable release and manifest contract. Under the shared
  server lock, derive a complete next release with the new CRL, updated manifest
  and persisted CRL sequence from the current accepted records, validate it,
  then activate atomically. Never edit the active release in place. Refactor lock
  ownership only as needed to avoid nested locks and snapshot/activation races.
  Controller publication must reconcile with this generated state rather than
  reinstall its own older CRL; same-membership reapply must preserve the result.
- Serialize revocation/publication with renewal. A renewed CRL after a new revoke
  must contain that revocation, and a stale input must never roll it back. Retry
  a still-current signed result after activation failure; regenerate if inputs
  or validity changed. Preserve server-key-transition barriers. The publisher's
  success check must verify the reconciled release, not insist on its old CRL bytes.
- The local command uses the protected CA key and persistent records without
  SSH/`su` or controller credentials. Missing/wrong key, corrupt input or unusable
  CRL must fail closed with actionable status. A not-yet-due check is a no-op.
- Record last verified renewal and expiry; reuse the server notification
  integration for failures, with local status/logs if delivery also fails.
  Do not restart unrelated WireGuard state merely for an OpenVPN CRL refresh;
  retain the required OpenVPN revocation/disconnection behavior.
- Update the manual Make action to trigger/reconcile the server renewal path.
  Update compromise recovery to require fresh CA trust and explicit re-enrollment
  once the CA has been provisioned to the VPS. Preserve ordinary replacement
  behavior when no compromise occurred and current local records are available.
- Verify with synthetic CA/client material: controller offline, boot catch-up
  past expiry, threshold no-op, signature/permissions, revoked-client rejection,
  concurrent revocation, stale controller publication, sequence persistence,
  activation failure/retry, missing key, notification failure and fresh-CA recovery.
  Run a real scheduled renewal and reboot/reapply on a disposable Ubuntu VM.

Technical basis checked on 2026-11-01: OpenSSL's
[ca reference](https://docs.openssl.org/3.6/man1/openssl-ca/) describes signing
certificates and CRLs with a CA key and database; its database locking warning
requires external synchronization. The
[systemd timer reference](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html)
documents calendar scheduling and persistent catch-up. These references support
the proposed mechanism; they are not evidence that Bastion implements it.

## Historical manual-renewal/UFW verification notes

The existing manual CRL action is `make vpn-renew-open VPN_HOST=...`. The earlier
weekly operator procedure is only an interim workaround, superseded as target
behavior by autonomous server renewal. It retains the existing CA database and identity files. A renewal
needed by an unfinished add/revoke saves the new CRL while preserving that
operation, then requires its original retry to publish; server-key transitions
retain their existing apply/retry barrier. OpenSSL's primary
[ca reference](https://docs.openssl.org/3.6/man1/openssl-ca/) documents the
CA database and `-gencrl` contract used here.

UFW's managed manifest now includes its after rules, initialization hooks,
sysctl and enabled configuration. Legacy v1 adoption checks previously omitted
inputs before expanding the manifest. An in-progress marker is written before
policy mutation; retry validates package/target inputs and the permitted partial
rules, and an active resumed apply reloads the policy even when template files
already match. Unchanged completed applies do not create the marker.

Before the automatic-renewal correction, root's combined `make test` passed with synthetic inputs, including the three
CRL tests, four authority-marker tests, seven retry tests, policy-input and manifest fixtures
and the existing suites. The three production playbooks passed syntax checks;
strict validation passed for all six specs and three active changes. Existing
VPN static assertions were corrected to match literal status parentheses and
use the behavioral route-direction checks already in the suite.

Runtime evidence is recorded separately below when available. Historical VM
logs do not verify this revision. No live VPS or Telegram delivery is authorized.

Canonical UFW data is taken from actual Ubuntu package layout: only defaults
and sysctl are relevant dpkg conffiles; before/after rules, initialization hooks
and ufw.conf are compared with `/usr/share/ufw` skeletons. Captured native
IPv4/IPv6 user-rule scaffolds are regression fixtures; tests execute the real
inspection task and prove extra ACCEPT rules and table sections remain visible
for rejection. Manifest validation accepts only the complete old five-path or
current eleven-path set.

On the disposable COW Ubuntu fixture `/tmp/bastion-ufw-runtime.MedBTX/`,
`root-fresh-2.log` recorded the corrected fresh firewall apply with
`ok=52 changed=14 failed=0` and fresh authenticated SSH. `root-repeat.log`
recorded unchanged reapplication with `ok=56 changed=0 failed=0`.
The first fresh attempt failed closed before mutation because it exposed the
incorrect assumption that every policy file is a dpkg conffile; that assumption
was corrected before the successful runs. These are synthetic firewall-role
checks, not a full VPN packet-matrix, provider or live-server verification.

`root-pending.log` completed both interrupted-apply scenarios with exit 0 and
`ok=141 changed=13 failed=0`: partial template/rule writes were reconciled, and
an apply whose files already matched forced reload and removed deliberately
inserted stale IPv4/IPv6 kernel rules. Both scenarios verified the committed
manifest and removal of the pending marker. Fresh authenticated SSH also passed.

Earlier manual-renewal/UFW combined tests are recorded in
`/tmp/bastion-review-final-make-test.log`; they do not close task 2.1 for
autonomous server renewal.
Scoped firewall ansible-lint passed its production profile with no failures or
warnings, and the final combined implementation diff was reviewed. Full-repository
lint was not rerun (five previously recorded unrelated findings remain); the full
VPN packet-matrix and reboot suites were not rerun. No live VPS was changed and
no real credentials or Telegram messages were used.
