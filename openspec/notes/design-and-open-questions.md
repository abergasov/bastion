# Design proposals and open questions

Transferred from AGENTS.md on 2026-10-19. This document is non-normative: proposals are not approved decisions. Where the original discussion repeats a confirmed constraint, the normative requirement lives in [the specifications](../README.md). Resolve choices with the owner before implementing the affected behavior.

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

## Credential ownership proposals

- Proposed ownership: local encrypted OpenVPN CA/issuance records; server holds only its own private material, current CRL, and protected persistent WireGuard peer state. Keep membership/revocation state outside NixOS system generations so a system rollback cannot restore old membership. Nix owns services/networking, not a second competing peer list. Backups/restores must reconcile current revocations before exposing VPN listeners. The no-reauthorization invariant is required; this storage layout remains a proposal.
- Prefer device-generated keys where practical; locally generated profiles for mobile import are a proposal. Private-key retention and re-export behavior must be explicit.
- Decide whether peer membership is declarative or maintained in protected runtime state before implementing lifecycle commands. Avoid competing sources of truth.
- For active OpenVPN revocation, choose and test a local-only management mechanism or agree on and document a brief service restart. The acceptable interruption remains open.

## Questions still open

- Concrete server size, public addresses, and tooling for the agreed automated SSH installation. Architecture, public IPv4/IPv6, IP-only endpoints, UDP/443 for WireGuard, and recreation instead of console/rescue recovery are agreed.
- IPv6 routing inside both VPNs (discussion item 8 remains unanswered), final DNS provider and direct versus forwarded DNS, client-to-client/local-network access, and full-tunnel/kill-switch setup for Android, iOS, Windows, macOS, and Linux. Expected client count and no artificial quotas are agreed.
- Administrator key type (including optional hardware-backed keys), sudo password policy, and root account policy; no console recovery requirement.
- Credential restoration versus fresh issuance when recreating a server, and handling a changed endpoint IP in client profiles. Recreation must not silently re-authorize revoked credentials.
- Finalize off-server CA storage/backup, runtime peer state, and acceptable brief interruption if OpenVPN revocation requires a service restart. The local Makefile interface and single-host scope are already agreed.
- Required notification delivery guarantees, update cadence, maintenance windows, and backup destination.
