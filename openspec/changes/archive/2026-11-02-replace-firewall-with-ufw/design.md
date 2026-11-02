# Design

## Context

See [proposal.md](proposal.md) for motivation. The owner explicitly selected
replacement of the current firewall with UFW on 2026-11-01. The local role,
playbook wiring and static contract below are implemented; runtime results
remain distinct from that source-level evidence.

## Implementation evidence and limits

`collections/requirements.yml` pins `community.general` at `13.5.0`. On the
local controller, `ansible-galaxy collection list community.general` reported
that exact version and `ansible-doc community.general.ufw` resolved its module.
`ansible-core` is `2.21.5`. Focused static checks, all production playbook
syntax checks and `make test` passed locally after the role was added.

The controller itself has no UFW, `iptables-restore` or `ip6tables-restore`.
Those package contracts were instead inspected in a disposable Ubuntu 26.04
fixture. The clean disposable QEMU suite completed on
`/tmp/bastion-vpn-vm.Y1k727/` (controller log
`/tmp/bastion-vpn-clean-final.log`). It passed all migration safety gates
(invalid-interface validation, stale-policy rejection without changes, injected
UFW-enable failure, and injected fresh no-mux SSH failure), each retaining the
legacy protection. It then passed normal migration, unchanged reapply
(`ok=77`, `changed=0`), WireGuard lifecycle recovery, dual-stack ingress and
peer packet matrices, UFW reload, and the true eight-flow seeded-established
isolation check. Its final revocation/reboot/reapply tail passed with
`ok=77`, `changed=1` only for fixture-state copy, fresh denial for revoked
client A and active/reconnected client B; the suite ended with the VPN VM
terminal marker. These are protected synthetic logs and may disappear after a
host restart. The distinct recovery result and final review closure are recorded
below. No VPS, real secret, or Telegram endpoint was used.

The final recovery gate used the existing cross-component VM suite rather than
the aggregate `recovery-integration-test` wrapper: the latter reruns the same
full VPN VM suite already required as the fresh clean gate. The selected suite
independently exercised firewall/VPN/secrets/notification role recovery,
idempotent reapply and reboot. It passed on
`/tmp/bastion-recovery-cross-component.rYg5Vs/` (controller log
`/tmp/bastion-recovery-cross-final.log`): initial apply `ok=116 changed=63`,
repeat `ok=109 changed=0`, reboot 103 seconds, then
`RECOVERY_CROSS_COMPONENT_VM_PASS`.

The targeted continuation completed as `RESUME_AFTER_INGRESS_LIVE_PASS`: UFW
reload, seeded isolation, client-A revocation with client-B continuity and
reconnect, reboot (98 seconds), reapply (`ok=77`, `changed=1` only for fixture
state copy), and revoked-client denial after reboot all passed. It is staged
reuse of a protected synthetic fixture, corroborated rather than replaced by
the completed fresh clean run above.

The synthetic socket transport needed static IPv6 neighbours after packet
captures showed the server accepted/responded to NS/NA while peer-side dynamic
neighbour resolution did not complete. This is a fixture-only transport
limitation; it must not be treated as a production UFW allowance change or as
evidence for provider-network IPv6 behaviour.

The role records a `bastion-ufw-state-v1` marker and checksums its managed UFW
inputs. It accepts only fresh package state or that exact known state before
mutation, including when UFW is inactive. A future managed policy migration
must explicitly accept the prior marker version, apply its new policy and write
the next version; it must not silently adopt custom rules.

Read-only inspection of the current local working tree found:

| Source | Observed behavior |
| --- | --- |
| `roles/vpn/templates/90-bastion-vpn.nft.j2` | Replaces only `inet bastion`. Input defaults to drop; permits loopback, established/related, ICMP/ICMPv6, TCP/22, TCP/443 and UDP/443. No output chain. |
| Same template, forward chain | Drops all four interface pairs between `tun-openvpn` and `wg-bastion` before established/related; allows either tunnel to `netplan_interface`; otherwise drops. |
| Same template, postrouting | Masquerades `10.42.0.0/24`, `10.43.0.0/24`, `fd42:1::/64`, `fd42:2::/64` toward the configured uplink. |
| `roles/vpn/tasks/main.yml` and handlers | Install nftables, write the table and forwarding sysctls, enable/restart the custom firewall unit. |
| `bastion-nftables.service.j2` | Loads the table at boot before fail2ban; has no `ExecStop`, so stopping the unit alone does not remove the table. |
| `bastion-vpn-apply.service.j2` | Requires and follows the custom firewall and secrets units. |
| `roles/administration/tasks/main.yml` | Enables the packaged SSH jail; does not select a custom ban action or override jail timing. |
| Legacy `/home/alejandro/go/src/ansible/roles/ufw/tasks/main.yml` | Allows TCP/22,80,443, the configured SSH port and configurable UDP VPN ports; enables UFW twice. This role does not define dual-stack VPN NAT or peer isolation. |

The legacy VPN installer role is commented out in its playbook. Neither that
repository nor this checkout proves what currently runs on a live server.
Secrets were not opened. Existing unrelated working-tree changes are outside
this proposal. Main specs already define the required packet policy; the delta
adds the owner-selected management interface and transition guarantees.

## Goals / Non-Goals

**Goals:** one owner for Bastion's static firewall, native UFW persistence,
and a testable migration preserving the existing network contract.

**Non-Goals:** changing VPN pools, profiles, credentials, ports or fail2ban
timing; introducing Docker support, a second firewall manager, firewall backend
selection, automatic rollback daemons or new management commands. No deployment
or end-user application certification belongs to this planning change.

## Decisions

### 1. A small firewall role owns UFW

Add `roles/firewall/` using Ubuntu's `ufw` package and
`community.general.ufw` for supported policy/rule operations. Pin the collection
in `collections/requirements.yml` and document installation for operator and
test environments. The module is not bundled with `ansible-core`; its rule
operations must run sequentially. These capabilities are documented in the
[Ansible module reference](https://docs.ansible.com/projects/ansible/latest/collections/community/general/ufw_module.html).

Wire the role into bootstrap/site after administration and before VPN activation.
Keep the existing forwarding sysctl owner in the VPN role; ensure UFW's sysctl
loading does not undo it. Remove only obsolete firewall responsibilities from
that role. Use the packaged `ufw.service` for boot ordering in the VPN apply unit,
with Ansible verifying that UFW is actually enabled and loaded before starting
VPN services. Retain the existing secrets dependencies and cleanup behavior.

Keeping firewall configuration inside VPN would retain mixed ownership.
Custom shell wrappers around every UFW operation would duplicate the module's
convergence behavior. Neither is needed. Do not purge the nftables package:
the backend and fail2ban can still use netfilter/nftables while UFW owns the
static policy.

### 2. Preserve the effective packet policy

Set IPv6 enabled, default incoming deny, outgoing allow and routed deny. Add
only TCP/22, TCP/443 and UDP/443 service allowances. Allow each VPN interface to
the existing uplink without destination or port filtering. Do not set a global
forward-allow default. Keep provider-private/metadata access under the existing
unrestricted egress requirement.

Use UFW's native `before.rules` and `before6.rules` for the parts its CLI cannot
express with the required ordering: the four tunnel-to-tunnel drops must precede
the forward established/related acceptance, and family-specific NAT must retain
the four existing pools and uplink. Preserve necessary loopback, control and
return traffic. Review packaged rules for extra service allowances, including
multicast discovery, and omit those inconsistent with Bastion's narrow ingress
contract. Preserve required provider control traffic and existing IPv6 routing.

The [UFW framework manual](https://manpages.ubuntu.com/manpages/resolute/man8/ufw-framework.8.html)
documents before/user/after ordering, custom table sections, separate IPv6 files,
sysctl loading and the limited visibility of `ufw status`. Use native file
templates with syntax validation, not an independent rules loader. Include
`ufw show raw` and family-specific save/inspection output in verification.

Ordinary route-deny rules alone are insufficient if an earlier return-traffic
rule already accepts a packet. Native nftables plus UFW would leave competing
static owners; it is permitted only temporarily during the ordered handover.
NAT66 availability and actual dual-stack packet flow must be demonstrated on
the selected Ubuntu kernel rather than inferred from a rendered template.

### 3. Preserve fail2ban ownership and reject conflicts early

Keep the packaged SSH jail policy. Record its actual ban action/backend on the
Ubuntu 26.04 fixture, including where it executes relative to UFW. Configure UFW
not to flush unrelated built-in chains (`MANAGE_BUILTINS=no`); the framework
manual documents this coexistence setting. Verify active IPv4 and IPv6 bans
through migration and reload with new connection attempts. Do not restart
fail2ban on every apply, add UFW rate limiting, or treat a listed ban as proof
that packets are blocked. If backend integration needs an explicit action,
change only that integration and prove the packaged jail policy remains intact.

Before mutation, inspect the existing UFW state and competing static loaders.
Support a fresh package configuration or the known Bastion-managed state; report
unexpected custom rules/loaders as conflicts with instructions to resolve them.
Do not silently merge stale allows (such as TCP/80), use `ufw reset`, flush the
whole ruleset, or remove another application's tables. The old Bastion service
and table are the recognized migration source, not an unknown conflict.

### 4. Reuse and extend the existing verification paths

| Surface | Planned change |
| --- | --- |
| `tests/vpn-static-test.sh` | Replace nft template assertions and the current prohibition on UFW; cover policy, rule order, IPv6/NAT and no global reset. |
| `tests/vpn-vm-test.sh`, `tests/vpn-vm-peer-matrix.sh`, `tests/vpn-vm-guest-test.sh` | Add the firewall role to the fixture and exercise real packet behavior, transition failures, reload, reboot and unchanged apply. |
| `tests/device-lifecycle-vm-test.sh` | Update its explicit role list and retain lifecycle/revocation behavior under UFW. |
| `tests/recovery-vm-cross-component.sh`, `tests/recovery-integration-test.sh` | Include firewall configuration in cross-component recovery and preserve local notification mocks. |
| `playbooks/bootstrap.yml`, `playbooks/site.yml`, `roles/vpn/` | Establish role ordering, migration cleanup and the new boot dependency. |
| `collections/requirements.yml`, installation instructions and test setup | Supply the pinned collection before syntax/lint/VM checks. |
| `docs/vpn-connectivity.md`, `docs/installation.md`, `docs/maintenance.md`, `docs/verification.md` | Describe UFW inspection, safe transition, dependency setup and new evidence without rewriting archived nftables results as UFW evidence. |

The existing peer matrix proves IPv6 TCP/443 firewall admission with a test
listener; OpenVPN itself is currently tested on an IPv4 transport. Retain that
distinction. Test unwanted TCP and UDP listeners and packaged extra allowances,
not just closed ports. Exercise established/related isolation in a disposable
fixture without briefly opening peer access on a live host.

## Risks / Trade-offs

- SSH lockout during activation → install the SSH allowance first, preserve
  the administrative session, and verify a fresh authenticated connection from
  the controller before retiring the old table.
- Overlapping old/new NAT and forwarding during migration → keep overlap brief
  and test real traffic during and after handover; remove only `inet bastion`.
- UFW acceptance order bypasses isolation or bans → inspect effective chains
  and test denied traffic, active bans and seeded connection tracking.
- UFW service presence is mistaken for protection → verify enabled/loaded
  policy as well as boot ordering and failure behavior before VPN activation.
- UFW reload or sysctl application breaks IPv6 → verify forwarding, necessary
  ICMPv6/provider control traffic, source translation and both egress families
  after apply, reload and reboot.
- Existing checks encode nftables file names → update all listed callers and
  fixtures together, retaining behavioral coverage and old evidence provenance.

## Migration Plan

Implementation is a broad networking/security task: one `tech_lead` owns its
investigation, implementation, focused tests and one final review. Use both the
OpenSpec apply workflow and the required `task` skill, locating them first.
This approved change is in that workflow; only the source-level portions with
recorded evidence are complete.

1. In isolated Ubuntu 26.04 fixtures, record package/collection versions and
   validate native rule syntax, UFW defaults, fail2ban backend, sysctls and unit
   ordering. Exercise both a fresh host and the current nftables configuration.
2. Check conflicts before mutation. Prepare complete UFW policy with SSH allowed;
   retain the running old policy and its restorable files during migration.
3. Activate UFW while retaining the old policy. Verify its loaded state, fresh
   authenticated SSH and preserved bans. Fail fast on errors. Use ordinary
   Ansible error handling; do not build a separate transaction service.
4. Update VPN dependencies without unnecessarily restarting VPN services. Only
   after successful verification, disable/remove the obsolete unit and delete
   `inet bastion` explicitly (stopping the old unit alone leaves it installed).
   Remove the old rule file and reload systemd. Keep other tables intact.
5. Verify connectivity, isolation and bans after handover, then unchanged apply
   and reboot. Repeat the relevant lifecycle/recovery checks with UFW.
6. Before legacy retirement, rollback restores any changed dependency/config
   files and the retained old table before disabling the failed replacement.
   After retirement, documented rollback from the held session restores the
   prior Bastion files/unit/table before disabling UFW; never flush unrelated
   rules. If all administrative access is lost, the existing recovery contract
   is server recreation. No automatic rollback daemon is proposed.
7. Record results and exclusions. Live rollout remains a separate authorized
   operation with the same administrative-access precautions.

## Open Questions

Only Ubuntu runtime/backend verification remains: installed UFW/fail2ban
versions and effective fail2ban ban action must be recorded during fixture
execution. These do not change the owner-approved UFW replacement or the
packet-policy requirements. The official
[Ubuntu firewall guide](https://ubuntu.com/server/docs/how-to/security/firewalls/)
and the linked UFW/Ansible references were checked on 2026-11-01; no runtime
compatibility result is claimed.
