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
SOPS/age and recipient separation remain requirements; the source project's use
of Ansible Vault does not itself change Bastion's storage design.

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

The six stages below target Ubuntu/Ansible. Stages 1 and 2 are complete and archived;
four changes remain active. Tasks remain incomplete until implementation and
relevant checks provide evidence. Historical NixOS checks do not satisfy them.

| Order | Change | Dependencies |
| --- | --- | --- |
| 1 | [Ubuntu platform and provisioning — complete](changes/archive/2026-10-23-implement-ubuntu-platform/proposal.md) · [tasks](changes/archive/2026-10-23-implement-ubuntu-platform/tasks.md) | None |
| 2 | [Ubuntu secrets and administration — complete](changes/archive/2026-10-23-implement-ubuntu-secrets-administration/proposal.md) · [tasks](changes/archive/2026-10-23-implement-ubuntu-secrets-administration/tasks.md) | 1 |
| 3 | [VPN connectivity](changes/implement-vpn-connectivity/proposal.md) · [tasks](changes/implement-vpn-connectivity/tasks.md) | 1, 2 |
| 4 | [Device lifecycle](changes/implement-device-lifecycle/proposal.md) · [tasks](changes/implement-device-lifecycle/tasks.md) | 1, 2, 3 for server integration |
| 5 | [SSH and boot notifications](changes/implement-ssh-notifications/proposal.md) · [tasks](changes/implement-ssh-notifications/tasks.md) | 1, 2; independent of 3 and 4 |
| 6 | [Recovery, updates and final verification](changes/implement-recovery-and-updates/proposal.md) · [tasks](changes/implement-recovery-and-updates/tasks.md) | 1–5 for end-to-end verification |

Each change has a proposal, design and task list. `skip_specs: true`
ties these implementation plans to the approved baseline without duplicating it
as delta specifications. Future behavior changes use `openspec/changes/`.

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
