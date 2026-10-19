# Historical research — 2026-10-19

Transferred from AGENTS.md without rechecking upstream. These observations describe the inspected references, not an implemented Bastion server. Recheck relevant sources before implementation.

## Existing setup: reference, not a migration specification

The owner's previous Ansible project is `/home/alejandro/go/src/ansible`. Read it for behavior, but do not modify it as part of this project without an applicable request.

Observed in its playbook and roles:

- An administrator account (historically `admin`) receives an SSH public key and password-protected sudo. Passwords for admin and root come from variables.
- SSH disallows root login and password authentication and restricts allowed users.
- UFW opens SSH, TCP 80/443, and configurable UDP VPN ports; fail2ban reads `/var/log/auth.log`.
- Docker and various interactive/development tools are installed. These are not requirements for Bastion.
- `roles/ssh_keys` restores a private SSH key from a seed on the server. Do not reproduce this for inbound administrator access: only the administrator's public key belongs on the server.
- `roles/vpns` downloads interactive installers via `git.io`; the role is commented out in the main playbook. Do not infer actual live-server state from these files.
- `roles/gen_vpn` invokes those installers and downloads `.ovpn` and WireGuard `.conf` files. There is no corresponding revocation role in the inspected files.
- `roles/update_vpn` reboots unconditionally and repairs NAT rules after boot. NixOS should own persistent networking declaratively.
- `roles/ssh_notify` follows an unpinned checkout and passes Telegram credentials as Make command arguments. Replace this installation pattern with a pinned package and runtime secrets.
- The `secret` vault and its decryption credentials were not opened. Never copy passwords, seeds, tokens, private keys, or client profiles into this file or tool output.

## Initial technical findings

### ssh_notify

Inspected through GitHub MCP at commit `20d99f5050246dd450fbc57dfe4e44f1ae30e4bb`; recheck upstream before implementation.

- Reads `/etc/ssh_notify.conf` and tails a text log (default `/var/log/auth.log`); it does not consume journald directly.
- Its current login regex expects `sshd[PID]: Accepted`. OpenSSH 9.8 introduced `sshd-session` log tags. Treat compatibility with the selected NixOS OpenSSH logs as a required integration test, not an assumption.
- The startup message says the notification service started. It does not distinguish a system reboot from a service restart. The owner's reboot-notification requirement remains to be implemented explicitly.
- Old log entries are skipped at startup; failed sends are not retried or persisted. Telegram notifications are not a complete audit trail.
- The supplied unit implicitly runs as root and uses `/usr/bin/ssh_notify`. Package it with Nix and propose a dedicated user with read access only to the required log and configuration, plus appropriate systemd restrictions.
- Minimal integration candidate: a restricted text authentication log with rotation. Native journal input is a possible separate upstream change; do not assume it exists.
- Any necessary upstream changes must be explicitly scoped; analysis here does not authorize pushing changes to ssh_notify.

Sources: [README](https://github.com/abergasov/ssh_notify/blob/20d99f5050246dd450fbc57dfe4e44f1ae30e4bb/README.md), [reader](https://github.com/abergasov/ssh_notify/blob/20d99f5050246dd450fbc57dfe4e44f1ae30e4bb/internal/reader.go), [startup](https://github.com/abergasov/ssh_notify/blob/20d99f5050246dd450fbc57dfe4e44f1ae30e4bb/cmd/main.go), [OpenSSH 9.8 notes](https://www.openssh.org/txt/release-9.8).

### Previous OpenVPN tooling

Inspected [cfra/roadwarrior-vpn](https://github.com/cfra/roadwarrior-vpn/tree/797f740bb0f625db5c5e1db20ab16dbba9ff0ce7) through GitHub MCP.

- This project generates OpenVPN PKI/configurations; it is not a WireGuard manager or NixOS module.
- Its server template contains legacy `comp-lzo no` and `compress` framing, embeds private material, and requires manual review. This does not by itself prove active compression or an exploitable vulnerability.
- Its revocation script generates a CRL, but the README requires deploying it and configuring `crl-verify` separately. The generated server template does not enable that check.
- Prefer native NixOS services and established PKI tooling such as Easy-RSA rather than porting the installer. Maintenance status was not established from commit history.
