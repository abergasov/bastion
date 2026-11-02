# Bastion specifications

The target platform is **Ubuntu Server configured through Ansible**, following the
owner decision of 2026-10-23. A minimal Ubuntu/Ansible foundation now exists and
has passed isolated QEMU/TCG Ubuntu VM initial/repeated apply, reboot, native
logging and explicit package-update checks on 1 vCPU/2 GB/20 GB. This is not
evidence of live VPS/provider readiness, VPN throughput or server operation.
The retained NixOS archive is historical only.

## Specifications

| Capability | Scope |
| --- | --- |
| [server-platform](specs/server-platform/spec.md) | Ubuntu Server, Ansible provisioning, idempotence and manual updates |
| [vpn-connectivity](specs/vpn-connectivity/spec.md) | Server endpoints, forwarding, DNS settings and peer isolation |
| [server-administration](specs/server-administration/spec.md) | Admin-only key-authenticated SSH, account passwords, su and fail2ban |
| [device-lifecycle](specs/device-lifecycle/spec.md) | Make interface, credentials, export, revocation and consistency |
| [ssh-notifications](specs/ssh-notifications/spec.md) | SSH login and boot/reboot Telegram notifications |
| [recovery-and-verification](specs/recovery-and-verification/spec.md) | Recovery, secret protection, acceptance checks and safe rollout |

`SHALL` denotes a requirement. Scenarios define expected outcomes, not passing
tests. Platform changes preserve the agreed VPN, administration, device and
notification behavior except where a platform-specific mechanism is replaced.
Ansible Vault is the agreed storage design: password and ciphertext remain on
the controller, while the VPS receives only required root-owned server files.

## Supporting context

- [Ubuntu/Ansible transition](notes/ubuntu-ansible-transition.md) records the new
  decision, inspected local Ansible source, reusable parts and migration limits.
- [Design decisions and open questions](notes/design-and-open-questions.md)
  preserve chronological decisions and identify superseded NixOS choices.
- [Historical research](notes/research.md) preserves earlier observations;
  upstream versions and compatibility must be rechecked during implementation.
- [Agent instructions](../AGENTS.md) govern workflow and secret handling.

The source `/home/alejandro/go/src/ansible` remains read-only. The owner permits
copying needed secrets during implementation under the agreed protection rules.
Secrets were not decrypted or copied in this documentation update.

## Implementation plan

The six stages below target Ubuntu/Ansible. Stages 1–5 are complete and archived;
recovery and final verification remain active (13/15 tasks complete). Tasks remain incomplete until implementation and
relevant checks provide evidence. Historical NixOS checks do not satisfy them.

| Order | Change | Dependencies |
| --- | --- | --- |
| 1 | [Ubuntu platform and provisioning — complete](changes/archive/2026-10-23-implement-ubuntu-platform/proposal.md) · [tasks](changes/archive/2026-10-23-implement-ubuntu-platform/tasks.md) | None |
| 2 | [Ubuntu secrets and administration — complete](changes/archive/2026-10-23-implement-ubuntu-secrets-administration/proposal.md) · [tasks](changes/archive/2026-10-23-implement-ubuntu-secrets-administration/tasks.md) | 1 |
| 3 | [VPN connectivity — complete](changes/archive/2026-10-25-implement-vpn-connectivity/proposal.md) · [tasks](changes/archive/2026-10-25-implement-vpn-connectivity/tasks.md) | 1, 2 |
| 4 | [Device lifecycle — complete](changes/archive/2026-10-31-implement-device-lifecycle/proposal.md) · [tasks](changes/archive/2026-10-31-implement-device-lifecycle/tasks.md) | 1, 2, 3 for server integration |
| 5 | [SSH and boot notifications — complete](changes/archive/2026-10-31-implement-ssh-notifications/proposal.md) · [tasks](changes/archive/2026-10-31-implement-ssh-notifications/tasks.md) | 1, 2; independent of 3 and 4 |
| 6 | [Recovery, updates and final verification](changes/implement-recovery-and-updates/proposal.md) · [tasks](changes/implement-recovery-and-updates/tasks.md) | 1–5 for end-to-end verification |

The completed [Ansible Vault migration](changes/archive/2026-10-31-migrate-secrets-to-ansible-vault/proposal.md)
is also archived; its requirement changes are merged into the main specifications.
The remaining recovery tasks are 5.1 (live readiness) and 5.2 (optional destructive
recovery exercise); local QEMU integration task 4.1 is complete.

The completed [UFW firewall replacement](changes/archive/2026-11-02-replace-firewall-with-ufw/proposal.md)
is archived with all 13 tasks complete. Its requirements are merged into
[vpn-connectivity](specs/vpn-connectivity/spec.md), preserving SSH, dual-stack
VPN forwarding, NAT, isolation and fail2ban. Its implementation and local VM
verification are recorded in the archived [tasks](changes/archive/2026-11-02-replace-firewall-with-ufw/tasks.md)
and [design](changes/archive/2026-11-02-replace-firewall-with-ufw/design.md).
Subsequent review corrections and their separate evidence are tracked below.

Each implementation stage has a proposal, design and task list. `skip_specs: true`
ties these implementation plans to the approved baseline without duplicating it
as delta specifications. Future behavior changes use `openspec/changes/`.

The authorized [review corrections](changes/fix-review-findings/proposal.md)
track complete UFW policy-input validation, interrupted-apply recovery, automatic
CRL renewal on the VPS and current-authority digest synchronization. The owner
chose autonomous server signing on 2026-11-01: a protected CA-key projection is
allowed on the VPS, while client private keys and the Vault password remain
controller-only. Compromise recovery must replace that exposed CA. The existing
manual action now follows the server renewal path. Server scheduling, protected
key projection, activation, compromise-recovery adaptation and failure status/
notification are implemented and covered by synthetic regression checks. The
[tasks and verification](changes/fix-review-findings/tasks.md) still distinguish
that evidence from the pending disposable-VM timer, reboot and revoked-client
admission checks (1.6), and combined regressions and final diff review (2.1).
This change remains active with 6/8 tasks complete; no live readiness is claimed.

The historical [NixOS platform](changes/archive/2026-10-20-implement-nixos-platform/proposal.md)
and [NixOS secrets/administration](changes/archive/2026-10-20-implement-secrets-and-administration/proposal.md)
remain archived with their original evidence. Existing NixOS code, tests and
operator instructions remain historical until replaced during implementation.

Initial live provisioning requires separate authorization, completed components
2–5 and the automated integration gate in change 6. Live readiness checks follow
provisioning; a destructive live recovery exercise is optional and separately
authorized. No plan itself authorizes deployment or Telegram delivery.

Validate specifications and active plans with:

```sh
rtk openspec validate --specs --strict --no-interactive
rtk openspec validate --changes --strict --no-interactive
```
