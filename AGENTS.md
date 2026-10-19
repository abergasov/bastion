# Bastion: private NixOS VPN server

## Purpose and current scope

- Communicate with the owner in Russian.
- This repository will contain a reproducible NixOS configuration for a hardened private VPN server.
- Required services: OpenVPN, WireGuard, fail2ban for public SSH, and the owner's [ssh_notify](https://github.com/abergasov/ssh_notify) for Telegram notifications about SSH logins and server boots/reboots.
- Both VPN services must support adding and revoking individual devices and exporting client configurations. Deleting a downloaded profile is not revocation.
- The current request authorizes analysis, discussion, and this context document. NixOS implementation and deployment have not been requested yet.
- At initial inspection on 2026-10-19 there were no NixOS configuration files, build targets, or tests. Serena created `.serena/` project metadata.
- Keep confirmed requirements, proposals, and unresolved choices distinct. Update this file after the owner makes architectural decisions; do not silently promote proposals into requirements.

## Confirmed decisions from the owner

- Deploy a new server; no backward compatibility or migration of existing VPN credentials is required.
- Hetzner is the initial provider, but the configuration must also work with other providers. Keep provider-specific disk, boot, and network details in host configuration; do not require a Hetzner API for routine administration.
- Clients are phones, computers, and a tablet running Android, iOS, Windows, macOS, and Linux. All internet traffic must go through the VPN.
- SSH remains publicly reachable and accepts public-key authentication only. Password login is forbidden; do not require VPN connectivity or a public source-IP allowlist for administration.
- fail2ban is required.
- Manage credentials through simple Makefile commands from the administrator's computer, with separate targets per protocol: suffix `-wg` for WireGuard and `-open` for OpenVPN. Do not require a `VPN` argument or implement a second management interface without need.
- Target one server initially. Store its SSH destination in a Makefile variable such as `VPN_HOST`; routine commands must not require a `HOST` argument. If another server is needed later, extend this simply with another explicit variable/target as needed; do not build a multi-host inventory or selection framework now.
- Server architecture: x86_64, with public IPv4 and IPv6. No domain; use IP addresses as connection endpoints. Public dual-stack addressing does not yet settle IPv6 routing inside the VPNs.
- OpenVPN listens on TCP/443; WireGuard listens on UDP/443. TCP/443 is not an HTTPS service and neither port choice guarantees bypass of traffic filtering.
- Installation must be automated over SSH. `nixos-anywhere` with `disko` remains the proposed tool choice, not an explicitly selected requirement.
- Recovery policy: recreate the server after a failure rather than require console/rescue recovery. Do not make tested console access or an emergency root password a prerequisite. This does not authorize deployment or server deletion during analysis; credential preservation versus reissuance on recreation remains open.
- Expected use: 2–3 users with 3–4 devices each; separate VPN credentials for every device. Do not impose artificial client, device, bandwidth, or traffic quotas.
- Use a public DNS resolver: the owner accepts `1.1.1.1` or `8.8.8.8`. Final provider selection and direct client configuration versus a server-side forwarder remain open. DNS traffic must travel through the VPN.

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

## Proposed design — awaiting discussion

- Pin a supported stable NixOS/nixpkgs revision with a flake lock; pin ssh_notify source. The official download page listed NixOS 26.05 on the analysis date. Verify support again at implementation time and define an update/reboot schedule.
- Begin with small native modules for host configuration, administrative access/firewall, WireGuard, OpenVPN, and notifications. Avoid containers, a web administration panel, and orchestration frameworks unless a concrete requirement calls for them.
- Retain `admin`; use SSH keys only, explicitly disable password and keyboard-interactive SSH authentication, and prohibit root SSH login. Recommend a unique admin sudo password per host. Root account policy remains open, but console recovery and an emergency root password are not required under the agreed server-recreation policy.
- Keep public key-only SSH as confirmed above. Propose the native NixOS fail2ban SSH jail using the systemd journal and the selected firewall backend. Initial policy proposal: 5 matching failures within 10 minutes, a 1-hour ban, increasing on repeat offenses up to 24 hours. Scope bans to SSH ports, support IPv4 and IPv6, and provide status/unban instructions. Do not blanket-exempt VPN or private subnets. Verify actual log matching and ban/unban behavior. Reference: [NixOS fail2ban](https://wiki.nixos.org/wiki/Fail2ban).
- Default-deny inbound and forwarding rules, allowing public SSH, TCP/443 for OpenVPN, and UDP/443 for WireGuard. Do not open TCP/80, add an HTTPS service, or mark entire VPN interfaces trusted.
- Separate OpenVPN and WireGuard address pools. Propose client isolation within and across VPNs, and block access to provider private/metadata networks unless explicitly needed.
- Full-tunnel routing is confirmed. Route DNS through the VPN to the selected public resolver (`1.1.1.1` or `8.8.8.8`). A server-side forwarder is optional and not yet agreed; if used, expose it only to loopback/VPN. Choose dual-stack tunneling where the provider supports it; otherwise explicitly prevent client IPv6 bypass. Disabling IPv6 on the server alone is insufficient. Client kill-switch behavior and local-network exceptions must be specified and tested per operating system; a server configuration alone cannot enforce them.
- OpenVPN: individual client certificates, current AEAD configuration, no compression, server identity verification on clients, and tls-crypt-v2 if supported by all selected clients. CA private key preferably stays on a trusted administrative machine, with an encrypted backup.
- WireGuard: separate keypair per device; prefer generating private keys on the client. The server stores public peer identities and narrowly scoped allowed addresses. If exporting a generated private profile, use restrictive permissions and an explicit retention policy.
- Recommend sops-nix with age for runtime secrets, including Telegram credentials and server private keys. Never interpolate decrypted secrets into Nix expressions or derivations: `/nix/store` is readable by local users. Keep recovery decryption material off the VPN server.
- Keep operational logs with bounded retention; do not log VPN payloads or DNS query history by default. Telegram receives SSH metadata; agree on notification contents.
- No claim of absolute security: a VPS provider controls the host, and VPNs do not guarantee anonymity or bypass of traffic filtering.

## Credential lifecycle requirements for implementation

- Agreed command naming: `make vpn-add-wg CLIENT=phone` and `make vpn-add-open CLIENT=laptop`. Use the same protocol suffixes for `vpn-list-wg`/`vpn-list-open`, `vpn-revoke-wg`/`vpn-revoke-open`, and `vpn-export-wg`/`vpn-export-open`. Revoke is interactive: run `make vpn-revoke-wg` or `make vpn-revoke-open` without a `CLIENT` argument, show the selected protocol's clients, and prompt locally for the exact client name. Reject unknown names; empty input, EOF, or cancellation must leave state unchanged. Do not add a noninteractive revocation mode unless requested. Export takes `CLIENT`; list takes no client argument. The SSH destination comes from `VPN_HOST` in the Makefile. These targets are specified but do not exist yet. Keep Make as a thin entry point to existing tools and focused scripts; validate parameters before local shell or SSH use. Do not put passwords, tokens, or private keys in Make arguments.
- Proposed ownership: local encrypted OpenVPN CA/issuance records; server holds only its own private material, current CRL, and protected persistent WireGuard peer state. Keep membership/revocation state outside NixOS system generations so a system rollback cannot restore old membership. Nix owns services/networking, not a second competing peer list. Backups/restores must reconcile current revocations before exposing VPN listeners.
- Use authenticated SSH with host-key verification and sudo for privileged changes. Never report success until both persistent and live access state are updated and verified; clearly report partial failure. Profiles are private local files excluded from Git, with restrictive permissions. Prefer device-generated keys where practical; locally generated profiles for mobile import are acceptable as a proposal. Do not promise re-export of a private key that was never retained.
- Validate device names, public keys, addresses, duplicates, and path inputs before changing state. Never overwrite an existing private key implicitly.
- WireGuard revocation must remove the peer from the running interface and the persistent source loaded after restart/rebuild.
- OpenVPN revocation must deploy an effective CRL and terminate existing access promptly. A CRL update alone must not be presented as immediate disconnection. Choose and test a local-only management mechanism or document the agreed brief service restart.
- Verify CRL readability, validity, expiry handling, and behavior when it is missing. Do not assume a `crl-verify` line alone provides fail-closed behavior in every failure case.
- Decide whether peer membership is declarative or maintained in protected runtime state. Avoid competing sources of truth; use atomic updates and a simple lock if commands mutate shared state.
- A reboot, NixOS rebuild, rollback, or backup restore must not silently re-authorize revoked credentials. Define revocation-state ownership before implementing lifecycle commands.
- Keep PKI issuance records, current revocations, and necessary server secrets recoverable through encrypted backups. Git and system generations alone are not a backup of runtime state.

## Questions still open

- Concrete server size, public addresses, and tooling for the agreed automated SSH installation. Architecture, public IPv4/IPv6, IP-only endpoints, UDP/443 for WireGuard, and recreation instead of console/rescue recovery are agreed.
- IPv6 routing inside both VPNs (discussion item 8 remains unanswered), final DNS provider and direct versus forwarded DNS, client-to-client/local-network access, and full-tunnel/kill-switch setup for Android, iOS, Windows, macOS, and Linux. Expected client count and no artificial quotas are agreed.
- Administrator key type (including optional hardware-backed keys), sudo password policy, and root account policy; no console recovery requirement.
- Credential restoration versus fresh issuance when recreating a server, and handling a changed endpoint IP in client profiles. Recreation must not silently re-authorize revoked credentials.
- Finalize off-server CA storage/backup, runtime peer state, and acceptable brief interruption if OpenVPN revocation requires a service restart. The local Makefile interface and single-host scope are already agreed.
- Required notification delivery guarantees, update cadence, maintenance windows, and backup destination.

## Verification and safe rollout

- No Nix evaluation, build, or VM tests exist yet. Do not claim those checks have passed.
- Once implemented: run formatting/static checks appropriate to the chosen toolchain, `nix flake check`, and build the selected host's system closure.
- Add focused NixOS integration tests for both tunnels, permitted/blocked forwarding, public key-only SSH, fail2ban log matching and ban/unban on IPv4/IPv6, add/revoke across reboot/rebuild, secret permissions, and notification handling using a local mock endpoint.
- Test server recreation and any supported rollback/restore process; ensure revoked devices remain denied. Console/rescue testing is not required. Test missing/expired CRL behavior and active-client revocation.
- Verify real client DNS/IPv6 behavior, a fresh SSH login, log rotation, service restart, and actual reboot notification before declaring the server ready.
- Preserve a working administrative session when changing SSH, firewall, routing, or credentials. The agreed fallback after loss of access is server recreation; do not require a separate console/rescue workflow. A successful build is not proof of remote reachability.
- Report unrun checks and known exclusions explicitly. Do not deploy or alter a live server as part of a documentation-only task.

## Working conventions

- Use GitHub MCP first for remote repository metadata/files/diffs. State when unavailable or insufficient; use web fallback only for information it cannot provide. Verify current technical claims against primary documentation.
- Activate this project in Serena before code work. Prefer Serena for symbol exploration, references, and edits; use shell/file tools for operations it cannot perform and for tests/builds/formatting/Git. Prefix shell commands with `rtk` as instructed by `/home/alejandro/.codex/RTK.md` when available.
- Use the smallest readable implementation. Reuse native NixOS modules and existing tools; avoid speculative abstractions, dependencies, lifecycle frameworks, and configuration switches.
- Preserve boundary validation, error handling, secret isolation, and necessary synchronization. Nontrivial new logic needs a focused regression test.
- Classify implementation scope before delegation. Handle small changes directly; delegate broad security/networking work to one `tech_lead` owning research, implementation, tests, and review. Root must not duplicate its child work.
- For GitHub PR review, spawn one `github_pr_reviewer` with `fork_turns="none"`. For other agents default to `fork_turns="none"` and provide scope, constraints, acceptance criteria, checks, and applicable instructions. Use at most one implementation reviewer and reuse it for follow-up review.
- If implementing an OpenSpec change, use both `openspec-apply-change` (artifacts/tasks) and `task` (engineering workflow). Locate those skills first; if unavailable, state the limitation instead of silently substituting a partial workflow.
- Never include real secrets in examples, logs, Git, this document, or command arguments. Do not send Telegram messages during analysis without authorization.
