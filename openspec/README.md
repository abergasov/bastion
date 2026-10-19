# Bastion specifications

These specifications capture the target behavior from `AGENTS.md` and subsequent
owner decisions as of 2026-10-19. They are a requirements baseline, **not a record of implemented or
verified functionality**. There are no NixOS configurations, management commands,
build targets, or integration tests yet. This migration authorizes documentation
only; it does not authorize implementation, deployment, or server deletion.

## Specifications

| Capability | Scope |
| --- | --- |
| [server-platform](specs/server-platform/spec.md) | Reproducible NixOS host, provider independence, installation |
| [vpn-connectivity](specs/vpn-connectivity/spec.md) | Protocols, endpoints, clients, full tunnel and DNS |
| [server-administration](specs/server-administration/spec.md) | Admin-only key-authenticated SSH, account passwords, su and fail2ban |
| [device-lifecycle](specs/device-lifecycle/spec.md) | Make interface, credentials, export, revocation and consistency |
| [ssh-notifications](specs/ssh-notifications/spec.md) | SSH login and boot/reboot Telegram notifications |
| [recovery-and-verification](specs/recovery-and-verification/spec.md) | Recovery, backups, acceptance checks and safe rollout |

`SHALL` denotes a requirement. Scenarios define expected outcomes, not passing
tests. Implementation must satisfy the baseline and resolve the choices relevant
to its scope; it must not silently turn proposals into requirements.

## Supporting context

- [Design proposals and open questions](notes/design-and-open-questions.md) retain
  the unapproved options, including local-network access, non-VPN secret provisioning,
  optional additional backups and recovery choices.
- [Historical research](notes/research.md) retains the Ansible observations,
  inspected upstream commits and source links. It was not revalidated during this
  migration and is not a migration specification.
- [Agent instructions](../AGENTS.md) govern how work is performed.

Future behavior changes belong in `openspec/changes/` using the configured
`spec-driven` workflow. There is no implementation change or completed task list
for this documentation migration. Keep approved requirements in `specs/` and
update the notes when the owner resolves an open choice.

Validate the specifications with:

```sh
rtk openspec validate --specs --strict --no-interactive
```
