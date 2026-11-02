# VPN connectivity

> Historical note: any SOPS/age fixture reference below predates controller-only
> Ansible Vault and is not a current runtime contract.

The `vpn` role uses native Ubuntu `openvpn` and `wireguard-tools`; the separate
`firewall` role owns UFW through `community.general==13.5.0`.
It exposes OpenVPN on TCP/443 and WireGuard on UDP/443; neither is HTTPS and
neither port is a promise to bypass filtering, anonymity or absolute security.
WireGuard is configured through the documented `ip link` and `wg set` flow in
the [WireGuard quick start](https://www.wireguard.com/quickstart/), so its
private key remains a runtime file rather than a tracked `wg-quick` config.

## Package and OpenVPN parameter review (2026-10-24)

The platform selects Ubuntu Server 26.04 LTS (Resolute), x86_64. Contrary to
the task's wording about "pinned Ubuntu packages", `roles/vpn/tasks/main.yml`
uses package names with `state: present`, without version pins or APT holds.
The following is a dated upstream reference, not an installed-version report
or a new package lock. Routine apply preserves installed versions; explicit
maintenance upgrades them and records `/var/lib/bastion/package-versions.txt`,
as required by [server-platform](../openspec/specs/server-platform/spec.md).

| Package | Reviewed Ubuntu amd64 version | Primary source |
| --- | --- | --- |
| `openvpn` | `2.7.0-1ubuntu1.4` security fix | [USN-8953-1, 2026-10-22](https://ubuntu.com/security/notices/USN-8953-1) |
| `openssl` | `3.5.5-1ubuntu3.5` | [Ubuntu package](https://packages.ubuntu.com/resolute/utils/openssl) |
| `wireguard-tools` | `1.0.20250521-1ubuntu1` | [Ubuntu package](https://packages.ubuntu.com/resolute/wireguard-tools) |
| `nftables` | `1.1.6-1` | [Ubuntu package](https://packages.ubuntu.com/en/resolute/nftables) |

The indexed OpenVPN package page still lists `2.7.0-1ubuntu1.3`; the newer
security notice specifies `.4` and requires a service restart after updating.
Before acceptance, compare installed versions and refreshed APT candidates
with current Ubuntu security notices. Do not treat an old installed package
as updated merely because `make apply` succeeds. No package was installed or
updated for this documentation review.

The template was checked against the [OpenVPN 2.7 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-7-manual/),
sections Protocol options, TLS Mode Options and Removed options:

| Area | Current choice and interpretation |
| --- | --- |
| Transport | `proto tcp-server`, `port 443`; retain the required TCP transport. |
| Cipher | `data-ciphers AES-256-GCM:AES-128-GCM`; the server selects the first mutually supported cipher. Keep this baseline pending measurement. |
| Auth | `auth SHA256` is supported, but GCM authenticates data itself; this option does not select the TLS cipher suite. |
| Compression | `allow-compression no`; no compression or compatibility fallback. |
| Control channel | TLS certificates, `verify-client-cert require`, `remote-cert-tls client`, CA and CRL checks; `dh none` disables finite-field DH. TLS cipher suites retain library defaults. |
| Extra control protection | No `tls-auth`, `tls-crypt` or `tls-crypt-v2` wrapper is configured. They are supported; v2 needs a server wrapping key and per-client material. |
| Fast I/O | Do not add `fast-io`: OpenVPN 2.7 ignores it. |

The existing server-secret/public-state contract has no wrapping-key material.
Keeping certificate-based TLS avoids inventing a second credential lifecycle
in this task. It does not provide the extra handshake concealment or pre-TLS
filtering of a wrapper. This is an implementation choice, not a requirement
that lifecycle must later enable v2. Required profile fingerprint pinning
remains owned by device lifecycle; certificate validation and CRL checks stay
enabled during every performance experiment.

For acceleration, [OpenVPN v2.7.0's DCO documentation](https://github.com/OpenVPN/openvpn/blob/v2.7.0/README.dco.md)
describes the Linux `ovpn` module included upstream from kernel 6.16 and
automatic DCO selection with fallback for unsupported configurations. TUN,
subnet topology, AEAD and no compression match its prerequisites. The template
leaves DCO selection automatic; this does not prove that the Ubuntu binary,
running kernel and TCP/443 session actually use it. In particular, upstream
lists `persist-tun`, used here, as untested. Record actual activation or
fallback and recheck isolation/recovery before accepting acceleration. Do not
install the older 2.6 `openvpn-dco-dkms` module or copy installer tuning flags.

## Routing and DNS

The configured pools are `10.42.0.0/24` and `fd42:1::/64` for OpenVPN, and
`10.43.0.0/24` and `fd42:2::/64` for WireGuard. UFW defaults to deny incoming
and routed traffic, allow outgoing traffic and permits TCP/22, TCP/80,
TCP/443, UDP/443, plus `ansible_port` as an additional TCP SSH rule (default
`22` when undefined). OpenVPN remains TCP/443 and WireGuard remains UDP/443.
The direct Ansible tasks add all SSH and inbound rules before enabling UFW once.
Its Bastion-managed `before.rules` and `before6.rules` retain only the policy
that native UFW rules cannot express: dual-stack NAT for these pools and the
four same/cross-tunnel drops before established/related forwarding; multicast
UPnP/mDNS allowances are absent. Inspect the effective policy with `ufw status
verbose`, `ufw show raw`, `iptables-save` and `ip6tables-save`; UFW status alone
does not show the custom NAT or ordering rules.

Static checks cover this declared policy. A disposable VM or live VPS apply is
separately authorized; no such result is claimed here.

OpenVPN advertises full tunnel routes and DNS in this order: `1.1.1.1`, then
`8.8.8.8`. The server supplies IPv6 egress and IPv4 fallback; a client OS or
application chooses a destination address family, so this does not promise
that every dual-stack connection uses IPv6 or prevent device-side DNS leaks.

## Public runtime state

Ansible contains no peer or client list. The future lifecycle owner publishes
an atomic symlink `/var/lib/bastion/vpn/current` to a root-owned immutable
release below `releases/`. A complete release contains only `READY`,
`manifest.sha256`, `wireguard/peers` (public key, IPv4, IPv6), and OpenVPN's
public `ca.crt`, `server.crt`, `crl.pem` and `metadata.json`. The ready marker
must read `bastion-vpn-state-v1`; the manifest covers exactly those five data
files. CA private keys and every client private key stay outside the VPS.

`bastion-vpn-verify-state` takes a shared `flock`, checks ownership, modes,
manifest, release identity, certificate chain, peer pools and the CRL signature
against the public CA before parsing its expiry. `bastion-vpn-apply-state` invokes the systemd apply service only after
validation; application takes the exclusive lock, rechecks the selected
release, configures WireGuard and restarts OpenVPN. A missing, unreadable,
invalid or expired CRL therefore fails the consumer before it reports
readiness. This is necessary because `crl-verify` alone is not proof of
fail-closed admission behavior.

`make apply` does not invent state or start VPN listeners without a complete
release. The lifecycle publisher must call `/usr/local/libexec/bastion-vpn-apply-state`
only after atomically replacing `current` while using the same lock.

## Verification and performance

`make test` includes a static contract check. `make vpn-vm-test` is an
non-interactive, disposable Ubuntu 26.04 QEMU step. By default it uses the
existing local foundation backing image and its recorded host key; callers may
override `BASTION_VPN_VM_BASE_IMAGE`, `BASTION_VPN_VM_PRIVATE_KEY` and
`BASTION_VPN_VM_HOST_KEYS`. Set `BASTION_VPN_VM_BOOTSTRAP_BECOME_PASSWORD_FILE`
to a mode-`0600` file with the foundation fixture's existing synthetic root
password. It creates a fresh qcow2 overlay, uses a generated synthetic SOPS
recipient and that mode-`0600` Ansible become-password file, and
never sends either value as an argument or environment variable. Set
`BASTION_VPN_VM_KEEP=1` only when a failed disposable run needs its protected
logs preserved. The focused playbook deliberately reapplies secrets,
administration and VPN in order, but not the platform/Netplan role, so its
loopback SSH fixture remains reachable. It uses `/tmp` Ansible state, creates
synthetic CA/client material only in the controller-side temporary peer
directory and a synthetic server key only in the protected runtime-secret path.
The VPS receives only public state. It checks listeners and trusted/forged/
expired CRL state. The controller used by this fixture has no `CAP_NET_ADMIN`,
`/dev/net/tun`, OpenVPN or WireGuard executable, so it cannot act as a client
without relaxing the boundary by putting client private material on the server.
The harness includes a second disposable QEMU peer overlay, with its private
material created and retained on the controller/peer. Staged isolated Ubuntu
QEMU evidence executed the valid/invalid-state lifecycle checks, config-change
restart, unchanged full apply (`changed=0`, `failed=0`), and the canonical peer
matrix twice consecutively. Both matrix runs passed OpenVPN and WireGuard
authentication/data exchange, IPv4/IPv6 forwarding, synthetic egress and DNS,
and same/cross-protocol isolation. This is not live-VPS evidence. Public-resolver
checks, throughput and CPU measurements remain unrun. The fixture does not
contact a public VPS.

### Task 2.1: controlled dual-stack egress (2026-10-24)

The existing pools, forwarding sysctls and dual-family masquerade required no
role changes. The peer matrix now connects IPv6-first to a synthetic dual-stack
TCP responder through both WireGuard and OpenVPN. It checks the responder's
destination and observed source (`2001:db8:100::1` for IPv6), then requires an
IPv6 `ECONNREFUSED` on a second port and a successful IPv4 connection with the
VPS source `192.0.2.1`. IPv4 remains available without blocking or delaying it.

The isolated Ubuntu 26.04 QEMU run passed initial apply, guest fixtures,
missing-state recovery, configuration restart and unchanged apply. Its first
matrix run exposed a test framing error (literal `\\n` instead of LF); this was
fixed and guarded by a local self-check and static check. The corrected matrix
was rerun on the same prepared disks after restoring the temporary test
network and peer inputs: `VPN_VM_PEER_MATRIX_PASS`, exit 0. Protected local
evidence: `/tmp/bastion-vpn-vm.6LOSjq/root-peer-matrix.log`. Bash syntax, VPN
static checks and strict OpenSpec validation passed; ShellCheck and shfmt were
unavailable. This is staged evidence, not a complete uninterrupted harness run.
It proves the controlled peer scenario, not address selection by end-user
applications or live provider connectivity.

### Task 2.2: IPv4/IPv6 inbound firewall (2026-10-24)

The `inet bastion` input chain has default-drop policy and permits only
established/related traffic, loopback, required ICMP/ICMPv6 control traffic,
TCP/22, TCP/443 and UDP/443. It has no output chain, destination/port egress
filter, or private/metadata exception. The isolated Ubuntu QEMU harness passed
`VPN_VM_FIREWALL_INGRESS_PASS` and `VPN_VM_PEER_MATRIX_PASS`, exit 0: it proved
SSH over IPv4/IPv6, real OpenVPN TCP/443 over IPv4, WireGuard handshakes over
IPv4/IPv6, and the IPv6 TCP/443 firewall path through a test-only listener.
A temporary listener on TCP/18082 timed out (rather than returning closed-port
refusal) over both families, proving default-drop for other new inbound TCP.
The same matrix proved unrestricted synthetic dual-stack tunnel egress while
preserving peer isolation. The IPv6 TCP/443 fixture proves the firewall path;
it does not claim OpenVPN itself accepts IPv6 connections. This is staged
synthetic-VM evidence only, not live VPS/provider acceptance.

### Throughput and CPU measurement plan

Execution belongs to `implement-recovery-and-updates` after live authorization;
none of these measurements has been run. Use the 1-vCPU, 2-GB resource class,
an independent OpenVPN peer and a controlled external dual-stack iperf3 server.
The destination must be outside both VPN pools: testing against another VPN
peer would conflict with isolation. Run the iperf3 listener on that external
host, never open an extra inbound port on Bastion. `iperf3` on the endpoints
and `sysstat` on the VPS are measurement prerequisites, not new role packages.

1. Record CPU model/features, `lscpu`, `uname -r`, `openvpn --version`,
   `openssl version -a`, `openvpn --show-ciphers`, and
   `dpkg-query -W openvpn openssl wireguard-tools nftables`. Capture
   `apt-cache policy openvpn openssl wireguard-tools nftables`, the negotiated
   cipher and DCO/fallback startup messages. Keep protected logs outside Git.
2. Measure the peer-to-destination and VPS-to-destination paths without the
   tunnel as separate reference runs. Then connect the peer over TCP/443 and
   confirm routes to both test addresses use its tunnel. Keep RTT, MTU, load
   and destination constant for comparisons.
3. On the peer, assign `BENCH_IPV4` and `BENCH_IPV6` to the controlled external
   server's literal addresses. Run each command three times, retaining each
   JSON result separately. The [iperf3 manual](https://software.es.net/iperf/invoking.html)
   defines the 5-second warm-up omission, 60-second measurement, single stream,
   address-family selection and reverse direction used here:

   ```sh
   iperf3 -4 -c "$BENCH_IPV4" -P 1 -O 5 -t 60 -J
   iperf3 -4 -c "$BENCH_IPV4" -P 1 -O 5 -t 60 -J -R
   iperf3 -6 -c "$BENCH_IPV6" -P 1 -O 5 -t 60 -J
   iperf3 -6 -c "$BENCH_IPV6" -P 1 -O 5 -t 60 -J -R
   ```

4. During each run, collect process CPU with
   `pidstat -u -p "$(systemctl show -p MainPID --value openvpn-server@bastion)" 1 75`
   and whole-VPS CPU with `mpstat -P ALL 1 75` in parallel terminals. Record
   user/system/softirq/steal time; DCO work is not all charged to the OpenVPN
   process. See Ubuntu's [pidstat manual](https://manpages.ubuntu.com/manpages/resolute/man1/pidstat.1.html)
   and [mpstat manual](https://manpages.ubuntu.com/manpages/resolute/man1/mpstat.1.html).
5. Compare the two configured AES-GCM ciphers by restricting the synthetic
   peer's `data-ciphers` to one at a time and reconnecting; confirm negotiation
   in logs. If CPU limits throughput, evaluate ChaCha20-Poly1305 separately
   only when supported by both binaries. Any server configuration experiment
   requires isolated regression checks before live activation. Compare DCO
   with userspace only if DCO is observed working on TCP/443; otherwise record
   why it is unavailable. Preserve authentication, pinning, revocation and
   IPv4/IPv6 isolation throughout; restore the baseline after experiments.
6. Report receiver Mbit/s median and range, bytes, duration, retransmissions,
   process and total CPU, resource use and bottlenecks for each cipher/family/
   direction. Select tuning from those results, not a presumed AES or DCO win.
   Repeat connectivity, DNS, isolation and recovery checks after changes.
   No throughput target or acceleration gain is established by this plan.

No live-VPS result is claimed by this document. The recorded QEMU checks are
staged evidence, not one uninterrupted final harness run.

### Task 3.3: OpenVPN CRL admission (2026-10-24)

The focused isolated Ubuntu QEMU fixture applied a valid public release: state
verification succeeded, OpenVPN was active, TCP/443 listened, and the test
confirmed its main process runs as root and can read the pinned
`/run/bastion-vpn/active` CA/certificate/CRL paths. It did not run an OpenVPN
peer handshake in this task's valid-state phase.

After atomic replacement of `current`, each missing, mode-`000`, syntactically
invalid, forged, and expired CRL was rejected by verify and apply. The observed
negative admission behavior was an inactive OpenVPN service and no TCP/443
listener, so a new client could not be admitted. Mode `000` is a contract
permission violation, not a claim that root receives kernel `EACCES`. The valid
release was restored (`VPN_VM_FIXTURE_PASS`). The parent harness was interrupted
only after this focused evidence and the subsequent missing-current recovery,
before its unrelated full reapply/idempotence and peer-matrix phases; it is not
reported as a full VM-harness pass or live-VPS evidence.

### Task 3.4: automation verification (2026-10-24)

A subsequent full isolated Ubuntu 26.04 QEMU harness completed with exit `0`:
initial apply (`ok=41 changed=28 failed=0`), lifecycle/CRL fixture
(`VPN_VM_FIXTURE_PASS`), missing-state stop/recovery, changed OpenVPN
configuration restart, final unchanged apply (`ok=34 changed=0 failed=0`),
inbound firewall (`VPN_VM_FIREWALL_INGRESS_PASS`), and peer matrix
(`VPN_VM_PEER_MATRIX_PASS`). It uses disposable 20 GiB overlays and a local
socket/loopback network only; it is not a VPS deployment or live acceptance.

`tests/vpn-static-test.sh`, its Bash syntax checks, and `git diff --check`
passed. `ansible-playbook --syntax-check` passed for bootstrap, site, and
maintenance with Ansible local state redirected to `/tmp`, because the
controller's default `~/.ansible/tmp` is read-only. The existing isolated
`/tmp/bastion-venv/bin/ansible-lint` passed the production profile with zero
warnings in 11 files. `shellcheck` and `shfmt` are unrun: neither binary is in
PATH or that venv, and this controller has no `apt-cache`; no project
dependency or system package was changed merely to format scripts. No live VPS,
public-resolver, throughput, CPU, or authorized rollout checks were run.

### Task 5.1: WireGuard fail-closed cleanup (2026-10-25)

`bastion-vpn-apply.service` already had a local, non-reentrant cleanup hook:
it stops OpenVPN, deletes `wg-bastion`, and removes the active links without
stopping the apply unit. Focused VM evidence found that its `ExecStopPost` is
not entered when `bastion-secrets.service` fails before the apply unit reaches
`ExecStart`. The VPN role now installs a secrets-service drop-in, after the
cleanup executable, that invokes the same idempotent cleanup in `ExecStopPost`;
the role reloads systemd before a later secrets restart.

A fresh disposable COW retry applied the role itself (`ok=16 changed=2 failed=0`:
the drop-in directory and template), while a prior role-only reapply of the
same production change was `ok=15 changed=0 failed=0`. It restored only the
harness's temporary socket-link addresses and test public key, and did not
contact a VPS. The checked-in lifecycle helper was extracted verbatim for this
focused retry. Its recovery is a transient systemd timer with a 30-second delay
and `AccuracySec=1s`: an SSH-session `nohup` helper would be killed when the
invalid secrets stop SSH before it could restore the fixture.

The retry observed a WireGuard handshake and ICMP traffic from the peer to
`10.43.0.1`, then: explicit apply stop removed runtime state and traffic was
denied; applying valid state restored traffic; an intentionally undecryptable
synthetic secrets file caused the secrets restart and apply dependency job to
fail before `ExecStart`, after which staged `wg-bastion` and active links were
removed and traffic was denied; the timer restored secrets, apply state,
interface, and traffic. Markers were
`VPN_VM_WG_LIFECYCLE_STOP_CLEANUP_PASS`, two
`VPN_VM_WG_LIFECYCLE_TRAFFIC_DENIED`,
`VPN_VM_WG_LIFECYCLE_FAILED_START_CLEANUP_PASS`, and
`VPN_VM_WG_LIFECYCLE_RECOVERY_PASS`, with focused sequence exit `0`.

The earlier full harness had already passed initial apply, changed configuration,
unchanged apply and peer matrix. The post-recovery peer matrix was not rerun in
this focused retry: the retained peer overlay had lost only reboot-volatile
synthetic client private keys while its server state still named their prior
public keys. This task's retry is therefore role-backed lifecycle evidence, not
a new single full-harness or peer-matrix pass. No live rollout, public resolver,
throughput, CPU, or end-user client claim follows from this evidence.
