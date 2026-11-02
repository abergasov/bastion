# Design

## Context

See [proposal.md](proposal.md). Current SOPS boot decryption needs a VPS age
identity; the confirmed Vault decision forbids both that identity and the Vault
password on the host. Existing consumers already use `/run/secrets`.

## Goals / Non-Goals

**Goals:** deliver minimum server secrets from controller Vault, preserve the
runtime interface across reboot, import required legacy values once without
exposure, and migrate owner authority persistence to Vault.

**Non-Goals:** deploy, contact Telegram, change legacy source, preserve an old
OpenVPN identity, or transmit CA/client/private SSH material.

## Decisions

### Controller Vault and persistent server store

`secrets/server.yaml` and owner authority become Ansible Vault ciphertext.
Ansible decrypts on the controller and writes individual required server files
through no-log/no-diff tasks to `/var/lib/bastion/secrets` (root `0700`, files
`0600`). A small activation service atomically rehydrates `/run/secrets` at boot.
Thus existing service paths remain stable while no secret-decryption key reaches
the VPS. Storing only volatile `/run` data was rejected because reboot would
need a Vault password; storing the whole controller Vault was rejected because
it contains owner-only material.

### Vault password and source import

The approved read-only legacy `vault.txt` is the controller password source; its
path, not password content, configures Ansible and it is never copied to Bastion
or the VPS. A protected temporary import uses the legacy Vault to read only `user_password`, `root_password`, `tg_token`
and `tg_chat`; passwords become SHA-512 hashes and notification configuration is
complete with fixed `SSHLogFile`, `ServerName = bastion` and Telegram fields.
It emits only Vault ciphertext. Seed, CA/client values and legacy VPN values are
excluded. Direct Make arguments and templates are rejected.

### Rotation and ordering

Lifecycle uses the same controller Vault mechanism for owner authority and
server-key replacement, with atomic ciphertext staging. The existing activation
ordering remains; a changed secret activation must reapply validated VPN state
because its cleanup hook stops VPN listeners.

## Risks / Trade-offs

- [Root VPS compromise reads persistent server secrets] → rotate all
  host-accessible values during compromise recovery; CA/client state remains off-host.
- [Controller Vault password loss] → Vault ciphertext becomes unavailable; use
  fresh owner authority and credentials rather than claim recovery.
- [Partial controller/server update] → use atomic local files and report partial
  failure; no live deployment is performed by this change.

## Migration Plan

1. Replace specifications, active plans and docs; preserve archives.
2. Replace SOPS/age role/input/preflight/lifecycle logic and create Vault
   ciphertext by protected import.
3. Verify static, syntax, focused and synthetic reboot/VM paths. Deployment and
   live secret rotation remain separately authorized operations.
