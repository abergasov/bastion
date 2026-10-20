# Bastion specifications

These specifications capture the target behavior from `AGENTS.md` and subsequent
owner decisions as of 2026-10-20. They are a requirements baseline, **not a record of implemented or
verified functionality**. There are no NixOS configurations, management commands,
build targets, or integration tests yet. This migration authorizes documentation
only; it does not authorize implementation, deployment, or server deletion.

## Specifications

| Capability | Scope |
| --- | --- |
| [server-platform](specs/server-platform/spec.md) | Reproducible NixOS host, provider independence, installation |
| [vpn-connectivity](specs/vpn-connectivity/spec.md) | Server endpoints, forwarding, DNS settings and peer isolation |
| [server-administration](specs/server-administration/spec.md) | Admin-only key-authenticated SSH, account passwords, su and fail2ban |
| [device-lifecycle](specs/device-lifecycle/spec.md) | Make interface, credentials, export, revocation and consistency |
| [ssh-notifications](specs/ssh-notifications/spec.md) | SSH login and boot/reboot Telegram notifications |
| [recovery-and-verification](specs/recovery-and-verification/spec.md) | Recovery, backups, acceptance checks and safe rollout |

`SHALL` denotes a requirement. Scenarios define expected outcomes, not passing
tests. Implementation must satisfy the baseline and resolve the choices relevant
to its scope; it must not silently turn proposals into requirements.

## Supporting context

- [Design proposals and open questions](notes/design-and-open-questions.md) retain
  decision history and remaining implementation choices. Notification wording
  and per-host installation inputs do not require a separate design decision.
- [Historical research](notes/research.md) retains the Ansible observations,
  inspected upstream commits and source links. It was not revalidated during this
  migration and is not a migration specification.
- [Agent instructions](../AGENTS.md) govern how work is performed.

Future behavior changes belong in `openspec/changes/` using the configured
`spec-driven` workflow. Keep approved requirements in `specs/` and update the
notes when the owner resolves an open choice.

## Implementation plan

The following changes plan implementation of the approved baseline. They do not
authorize implementation or deployment by themselves. Tasks remain incomplete
until implementation and the relevant checks provide evidence.

| Order | Change | Dependencies |
| --- | --- | --- |
| 1 | [NixOS platform and installation](changes/implement-nixos-platform/proposal.md) · [tasks](changes/implement-nixos-platform/tasks.md) | None; provides the foundation |
| 2 | [Secrets and administration](changes/implement-secrets-and-administration/proposal.md) · [tasks](changes/implement-secrets-and-administration/tasks.md) | 1 |
| 3 | [VPN connectivity](changes/implement-vpn-connectivity/proposal.md) · [tasks](changes/implement-vpn-connectivity/tasks.md) | 1, 2 |
| 4 | [Device lifecycle](changes/implement-device-lifecycle/proposal.md) · [tasks](changes/implement-device-lifecycle/tasks.md) | 1, 2, 3 for server integration |
| 5 | [SSH and boot notifications](changes/implement-ssh-notifications/proposal.md) · [tasks](changes/implement-ssh-notifications/tasks.md) | 1, 2; independent of 3 and 4 |
| 6 | [Recovery, updates and final verification](changes/implement-recovery-and-updates/proposal.md) · [tasks](changes/implement-recovery-and-updates/tasks.md) | 1–5 for end-to-end verification |

Each change contains a proposal, technical design and task list. `skip_specs: true`
keeps these implementation-only plans tied to the existing specifications without
duplicating them as artificial requirement changes.

Development dependencies do not imply that an intermediate host is ready for
deployment. Initial live installation requires separate authorization, completed
component work in changes 1–5 and the automated integration gate in change 6.
Its live readiness checks follow installation and remain required before claiming
server readiness; a destructive live recovery exercise is optional and separately
authorized. Component checks belong to their respective changes; the final change
combines them into recovery and readiness verification.

Validate the specifications with:

```sh
rtk openspec validate --specs --strict --no-interactive
```
