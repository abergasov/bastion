# Proposal

## Why

The current UFW role has grown a large manifest, interrupted-apply and
fresh-connection migration framework around a small static policy. The owner
authorized replacing that machinery with direct, readable Ansible UFW tasks.

## What Changes

- Replace policy ownership checks, state manifests, retry markers and the
  fresh-SSH helper with direct UFW package, policy, rule and enablement tasks.
- Permit TCP/22, TCP/80, TCP/443 and the configured Ansible SSH port; retain
  OpenVPN on TCP/443 and WireGuard on UDP/443.
- Retain the two UFW templates only for IPv4/IPv6 NAT and peer-isolation order,
  which native UFW rule tasks cannot express.
- Update the firewall contract, operator documentation and focused checks to
  describe the simplified declarative policy.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `vpn-connectivity`: allow TCP/80 and a configured SSH port, and replace
  migration/foreign-state guarantees with direct UFW policy convergence.

## Impact

`roles/firewall`, its obsolete helper and tests, VPN static checks, operator
documentation and the VPN connectivity specification. No dependencies, secrets,
deployment or VPN transport changes.
