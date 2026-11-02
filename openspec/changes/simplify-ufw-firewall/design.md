# Design

## Context

The role currently combines a static UFW policy with a large migration protocol.
See `proposal.md` and the VPN connectivity delta for the authorised behavior
change. UFW's documented routed rules express tunnel-to-uplink forwarding, but
not the required ordered raw NAT/isolation policy; the two existing templates
therefore remain.

## Goals / Non-Goals

**Goals:**

- Leave a short, top-to-bottom firewall role: validate the uplink, install UFW,
  install the required templates, set defaults, add ingress and route rules,
  enable it once.
- Keep TCP OpenVPN/443, UDP WireGuard/443, TCP/80 and both default/custom SSH
  access explicit and testable.

**Non-Goals:**

- Reconfigure VPN listener ports, pools, forwarding sysctls or fail2ban.
- Migrate or repair arbitrary pre-existing firewall policy, deploy a host, or
  add a replacement recovery protocol.

## Decisions

1. Keep `before.rules` and `before6.rules` for NAT and the early four-way
   isolation drops. Replacing them with only `community.general.ufw` would lose
   ordered isolation/NAT; retaining them is less code and preserves the
   requirement.
2. Use direct `community.general.ufw` rules for defaults, ingress and tunnel
   routes, followed by one `state: enabled`. The module documentation states
   that enablement reloads and starts UFW on boot; a separate service task or
   explicit reload would be duplicate machinery.
3. Keep TCP/22 and add `ansible_port` as an additional TCP rule. This retains
   default access while allowing the controller's actual SSH transport.
   OpenVPN remains fixed at TCP/443 and WireGuard at UDP/443; no unsupported
   UDP OpenVPN rule is added.
4. Remove Bastion manifests, package-state/raw-rule guards, apply markers,
   fresh-SSH helper, legacy-nftables retirement and their tests. The owner
   chose declarative policy over host migration/recovery orchestration.

## Risks / Trade-offs

- [A host has unrelated UFW/static-firewall customisation] → direct UFW tasks
  no longer reject it; inspect and migrate such state explicitly before an
  authorised live apply.
- [A wrong custom SSH port blocks future access] → the role adds TCP/22 and the
  configured `ansible_port` before UFW enablement; live operation remains
  separately authorised.
- [Template edit changes hidden forwarding policy] → retain a focused static
  test for all NAT pools and drop-before-conntrack order.

## Migration Plan

No host migration is performed in this change. On a separately authorised
deployment, the operator reviews existing firewall state, retains an
administrative session and verifies the resulting policy using the documented
UFW and iptables inspection commands.
