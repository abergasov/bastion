# Proposal

## Why

Bastion already enforces its network policy through a custom nftables table
owned by the VPN role. The owner chose UFW on 2026-11-01 as its replacement so
Ansible manages the host firewall through Ubuntu's standard UFW interface,
while preserving the existing SSH and VPN behavior.

## What Changes

- Replace `bastion-nftables.service` and `inet bastion` with an Ansible-managed
  UFW firewall, including persistent IPv4/IPv6 filtering and VPN masquerading.
- Preserve public SSH TCP/22, OpenVPN TCP/443, WireGuard UDP/443, required
  control/return traffic, unrestricted outbound traffic and same/cross-VPN
  client isolation. Do not copy TCP/80 or the old OpenVPN UDP settings from the
  read-only legacy Ansible role.
- Preserve fail2ban's packaged SSH jail policy and effective IPv4/IPv6 bans
  during firewall changes; establish safe installation and migration ordering.
- Remove the old Bastion firewall only after UFW is active and fresh SSH access
  works; update VPN boot dependencies and verify reapply/reboot behavior.
- Extend existing static and isolated VM checks for UFW, migration, rule order,
  fail2ban coexistence and rollback before the legacy policy is removed.

## Capabilities

### New Capabilities

None. Firewall behavior already belongs to `vpn-connectivity`.

### Modified Capabilities

- `vpn-connectivity`: require UFW as the persistent host/VPN firewall manager
  and define safe replacement of the existing Bastion nftables policy.
  Existing transport, forwarding, DNS and isolation requirements remain in force.

## Impact

- Add a small `roles/firewall/` role; wire it into bootstrap and routine apply
  before VPN activation. Move firewall ownership out of `roles/vpn/`; replace
  its firewall unit dependency and remove obsolete templates/handlers.
- Add a pinned `community.general` collection for `community.general.ufw` and
  document controller installation alongside the existing `ansible-core` pin.
  The host gains the Ubuntu `ufw` package; nftables may remain installed as a
  backend/diagnostic dependency without owning Bastion's static policy.
- Update the VPN, device-lifecycle and recovery VM fixtures that list roles
  explicitly, the nftables-specific static assertions, and operator firewall,
  installation and verification documentation. Keep archived evidence historical.
- Existing Bastion hosts require an ordered migration. No VPN identity, address
  pool, profile, public port, SSH account or inventory interface is changed.
- The local implementation replaces the static nftables ownership with UFW
  configuration. VM execution, live deployment and real Telegram delivery are
  not performed or authorized here.
