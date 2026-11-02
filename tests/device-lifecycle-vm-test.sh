#!/usr/bin/env bash
# One-server disposable lifecycle fixture.  All data remains below /tmp.
set -eo pipefail
umask 077

root=$(cd "$(dirname "$0")/.." && pwd)
assets=/tmp/bastion-vm-assets
base=$assets/resolute-lifecycle.qcow2
key=$assets/id_ed25519
known=$assets/known_hosts-lifecycle
password=$assets/bootstrap-password
wg_deb_cache=${BASTION_DEVICE_LIFECYCLE_WG_DEB:-}
port=${BASTION_DEVICE_LIFECYCLE_PORT:-32122}

usage() {
  echo "Requires the documented /tmp/bastion-vm-assets Resolute image, SSH key,"
  echo "known_hosts-lifecycle and a mode-0600 bootstrap-password fixture."
  echo "Set BASTION_VPN_VM_KEEP=1 to retain protected evidence on failure."
}
if test "${1:-}" = --resume-peer-probe-log-self-check; then
  check_dir=$(mktemp -d /tmp/bastion-device-lifecycle-probe-log.XXXXXX)
  trap 'rm -rf "$check_dir"' EXIT
  printf 'VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE\n' > "$check_dir/old.log"
  : > "$check_dir/current.log"
  if rg -q 'VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE' "$check_dir/current.log"; then
    echo 'resume peer probe self-check accepted a stale marker' >&2
    exit 1
  fi
  printf 'VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE\n' > "$check_dir/current.log"
  rg -q 'VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE' "$check_dir/current.log"
  echo DEVICE_LIFECYCLE_RESUME_PEER_PROBE_LOG_GUARD_PASS
  exit
fi
for path in "$base" "$key" "$known" "$password"; do
  test -r "$path" || { usage >&2; echo "missing: $path" >&2; exit 2; }
done
test "$(stat -c %a "$password")" = 600 || { echo "password must be mode 0600" >&2; exit 2; }
command -v qemu-system-x86_64 >/dev/null
command -v ansible-playbook >/dev/null
command -v ansible-vault >/dev/null
command -v openssl >/dev/null
command -v ar >/dev/null
command -v zstd >/dev/null
command -v bsdtar >/dev/null

install_pinned_collections() {
  local repo=$1
  local destination=$2

  command -v ansible-galaxy >/dev/null || {
    echo 'device-lifecycle-vm-test: ansible-galaxy is required to install pinned collections' >&2
    exit 2
  }
  ansible-galaxy collection install -r "$repo/collections/requirements.yml" -p "$destination" --force >/dev/null
  export ANSIBLE_COLLECTIONS_PATH="$destination"
}

# Resume a retained lifecycle server without ever replacing its 20 GiB overlay.
# The peer is always a fresh disposable VM.  This mode is intentionally opt-in:
# it needs the controller-only profiles emitted before the preserved revocation.
if test -n "${BASTION_DEVICE_LIFECYCLE_RESUME_DIR:-}"; then
  resume=$BASTION_DEVICE_LIFECYCLE_RESUME_DIR
  resume_password="$resume/controller/recovery-root-password"
  peer_password="$password"
  profiles=${BASTION_DEVICE_LIFECYCLE_PROFILE_DIR:-"$HOME/.local/state/bastion/vpn/profiles"}
  for path in "$resume/overlay.qcow2" "$resume/repo" "$resume/repo/secrets/server.yaml" \
      "$resume/repo/secrets/vpn-server.yaml" "$resume/controller/root-password" "$resume_password" \
      "$resume/controller/vault-password"; do
    test -r "$path" || { echo "device-lifecycle resume prerequisite is missing: $path" >&2; exit 2; }
  done
  test ! -e "$resume/.device-lifecycle-resume-unsafe" || {
    echo "device-lifecycle resume overlay was not shut down gracefully; refusing reuse: $resume/overlay.qcow2" >&2
    exit 2
  }
  test "$(stat -c %a "$resume_password")" = 600 || {
    echo "device-lifecycle resume recovery password must be mode 0600" >&2
    exit 2
  }
  if ! qemu-img info "$resume/overlay.qcow2" >/dev/null 2>&1; then
    echo "device-lifecycle resume overlay is locked by an existing QEMU; do not kill it from this test: $resume/overlay.qcow2" >&2
    exit 2
  fi
  reuse_run=0
  if test -n "${BASTION_DEVICE_LIFECYCLE_RESUME_RUN_DIR:-}"; then
    run=$BASTION_DEVICE_LIFECYCLE_RESUME_RUN_DIR
    reuse_run=1
    test -d "$run" && test -r "$run/peer.qcow2" || {
      echo "device-lifecycle resume run must contain a readable peer.qcow2: $run" >&2
      exit 2
    }
    qemu-img info "$run/peer.qcow2" >/dev/null 2>&1 || {
      echo "device-lifecycle resume peer overlay is locked or unreadable: $run/peer.qcow2" >&2
      exit 2
    }
    test ! -e "$run/.device-lifecycle-resume-unsafe" || {
      echo "device-lifecycle resume peer evidence was not shut down gracefully; refusing reuse: $run/peer.qcow2" >&2
      exit 2
    }
  else
    run=$(mktemp -d /tmp/bastion-device-lifecycle-resume.XXXXXX)
  fi
  install_pinned_collections "$resume/repo" "$run/collections"
  server_pid=''; peer_pid=''; known_backup=''
  cleanup_resume() {
    status=$?
    server_forced=0
    peer_forced=0
    if test -n "${server_pid:-}" && kill -0 "$server_pid" 2>/dev/null && test -r "$run/server.ini"; then
      ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su \
        --become-password-file "$resume_password" --ssh-common-args="${ssh_common:-}" \
        --module-name shell --args 'sync; systemd-run --no-block --collect --unit=bastion-device-lifecycle-cleanup /usr/bin/systemctl poweroff' >/dev/null 2>&1 || true
      for _ in $(seq 1 120); do
        if ! kill -0 "$server_pid" 2>/dev/null; then
          wait "$server_pid" 2>/dev/null || true
          server_pid=''
          break
        fi
        sleep 1
      done
    fi
    if test -n "${server_pid:-}"; then
      server_forced=1
      kill "$server_pid" 2>/dev/null || true
      wait "$server_pid" 2>/dev/null || true
      server_pid=''
    fi
    if test -n "${peer_pid:-}"; then
      peer_forced=1
      kill "$peer_pid" 2>/dev/null || true
      wait "$peer_pid" 2>/dev/null || true
      peer_pid=''
    fi
    if test "$server_forced" = 1; then
      : > "$resume/.device-lifecycle-resume-unsafe"
      echo "device-lifecycle resume server was force-terminated; marked overlay unsafe" >&2
    fi
    if test "$peer_forced" = 1 && { test "$reuse_run" = 1 || test "${BASTION_VPN_VM_KEEP:-0}" = 1; }; then
      : > "$run/.device-lifecycle-resume-unsafe"
      echo "device-lifecycle resume peer was force-terminated; marked evidence unsafe" >&2
    fi
    test -z "$known_backup" || cp "$known_backup" "$resume/repo/inventory/known_hosts"
    if test "$reuse_run" = 1 || test "${BASTION_VPN_VM_KEEP:-0}" = 1; then echo "DEVICE_LIFECYCLE_RESUME_EVIDENCE=$run"; else rm -rf "$run"; fi
    trap - EXIT
    exit "$status"
  }
  trap cleanup_resume EXIT
  port=${BASTION_DEVICE_LIFECYCLE_RESUME_PORT:-$((33000 + RANDOM % 2000))}
  peer_port=$((port + 1)); socket_port=$((port + 2))
  test "$socket_port" -le 65535 || { echo 'device-lifecycle resume port range is invalid' >&2; exit 2; }
  qemu-system-x86_64 -machine accel=tcg -m 2048 -smp 1 \
    -drive "file=$resume/overlay.qcow2,if=virtio,format=qcow2" \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=n0 \
    -netdev "socket,id=peer0,listen=127.0.0.1:$socket_port" -device virtio-net-pci,netdev=peer0,mac=52:54:00:12:34:57 \
    -display none -chardev "file,id=server_serial,path=$run/server-serial.log,append=on" -serial chardev:server_serial -monitor none >>"$run/server-qemu.log" 2>&1 &
  server_pid=$!
  for _ in $(seq 1 30); do
    kill -0 "$server_pid" 2>/dev/null || { echo 'device-lifecycle resume server exited before peer transport was ready' >&2; exit 1; }
    ss -ltnH "sport = :$socket_port" | awk '$1 == "LISTEN" { found=1 } END { exit !found }' && break
    sleep 1
  done
  ss -ltnH "sport = :$socket_port" | awk '$1 == "LISTEN" { found=1 } END { exit !found }' || {
    echo 'device-lifecycle resume peer transport did not listen' >&2
    exit 1
  }
  if test "$reuse_run" = 0; then
    qemu-img create -f qcow2 -F qcow2 -b "$base" "$run/peer.qcow2" >/dev/null
  fi
  qemu-system-x86_64 -machine accel=tcg -m 1024 -smp 1 \
    -drive "file=$run/peer.qcow2,if=virtio,format=qcow2" \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$peer_port-:22" -device virtio-net-pci,netdev=n0 \
    -netdev "socket,id=peer0,connect=127.0.0.1:$socket_port" -device virtio-net-pci,netdev=peer0,mac=52:54:00:12:34:58 \
    -display none -chardev "file,id=peer_serial,path=$run/peer-serial.log,append=on" -serial chardev:peer_serial -monitor none >>"$run/peer-qemu.log" 2>&1 &
  peer_pid=$!
  for _ in $(seq 1 30); do
    kill -0 "$peer_pid" 2>/dev/null || { echo 'device-lifecycle resume peer exited before transport connected' >&2; exit 1; }
    ss -tnH "( sport = :$socket_port or dport = :$socket_port )" | awk '$1 == "ESTAB" { found=1 } END { exit !found }' && break
    sleep 1
  done
  ss -tnH "( sport = :$socket_port or dport = :$socket_port )" | awk '$1 == "ESTAB" { found=1 } END { exit !found }' || {
    echo 'device-lifecycle resume peer transport did not connect' >&2
    exit 1
  }
  sed -E "s/\\[127\\.0\\.0\\.1\\]:[0-9]+/[127.0.0.1]:$port/g" "$known" > "$run/known_hosts"
  sed -E "s/\\[127\\.0\\.0\\.1\\]:[0-9]+/[127.0.0.1]:$peer_port/g" "$known" >> "$run/known_hosts"
  ssh_common="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$run/known_hosts -o StrictHostKeyChecking=yes"
  for n in $(seq 1 90); do /usr/bin/ssh -F /dev/null -i "$key" -p "$port" $ssh_common -o BatchMode=yes -o ConnectTimeout=3 admin@127.0.0.1 true >/dev/null 2>&1 && break; sleep 1; done
  /usr/bin/ssh -F /dev/null -i "$key" -p "$port" $ssh_common -o BatchMode=yes admin@127.0.0.1 true >/dev/null
  for n in $(seq 1 90); do /usr/bin/ssh -F /dev/null -i "$key" -p "$peer_port" $ssh_common -o BatchMode=yes -o ConnectTimeout=3 admin@127.0.0.1 true >/dev/null 2>&1 && break; sleep 1; done
  /usr/bin/ssh -F /dev/null -i "$key" -p "$peer_port" $ssh_common -o BatchMode=yes admin@127.0.0.1 true >/dev/null
  mkdir -p "$run/bin" "$run/work/profiles"
  cp "$resume/repo/inventory/known_hosts" "$run/known_hosts.before"; known_backup="$run/known_hosts.before"
  cp "$run/known_hosts" "$resume/repo/inventory/known_hosts"
  cat > "$run/bin/ssh" <<EOF
#!/usr/bin/env bash
exec /usr/bin/ssh -F /dev/null -i "$key" -p "$port" "\$@"
EOF
  cat > "$run/bin/scp" <<EOF
#!/usr/bin/env bash
exec /usr/bin/scp -F /dev/null -i "$key" -P "$port" "\$@"
EOF
  chmod 700 "$run/bin/ssh" "$run/bin/scp"
  cat > "$run/server.ini" <<EOF
[bastion]
bastion ansible_host=127.0.0.1 ansible_port=$port ansible_user=admin ansible_ssh_private_key_file=$key admin_authorized_key='$(<"$key.pub")' netplan_interface=ens3
EOF
  sed 's/^\[bastion\]$/[bastion_admin]/' "$run/server.ini" > "$run/maintenance.ini"
  cat >> "$run/maintenance.ini" <<'EOF'

[bastion_admin:vars]
netplan_interface=ens3
ipv4_address=10.0.2.15
ipv4_prefix=24
ipv4_gateway=10.0.2.2
ipv6_address=fec0::15
ipv6_prefix=64
ipv6_gateway=fec0::2
dns_servers=["10.0.2.3","fec0::3"]
EOF
  set +e
  ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$resume_password" --ssh-common-args="$ssh_common" --module-name command --args true >/dev/null 2>&1
  recovery_su_rc=$?
  set -e
  if test "$recovery_su_rc" -ne 0; then
    repair_password=${BASTION_DEVICE_LIFECYCLE_RESUME_REPAIR_PASSWORD_FILE:-}
    test -n "$repair_password" || {
      echo "device-lifecycle resume recovery su failed; set BASTION_DEVICE_LIFECYCLE_RESUME_REPAIR_PASSWORD_FILE for one-time repair" >&2
      exit 2
    }
    test -r "$repair_password" && test "$(stat -c %a "$repair_password")" = 600 || {
      echo "device-lifecycle resume repair password must be a readable mode-0600 file" >&2
      exit 2
    }
    ANSIBLE_LOCAL_TEMP="$run/ansible-repair" ansible-playbook -i "$run/server.ini" "$resume/repo/playbooks/device-lifecycle-vm.yml" --vault-password-file "$resume/controller/vault-password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$repair_password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common"
    ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$resume_password" --ssh-common-args="$ssh_common" --module-name command --args true
    install -m 0600 "$resume_password" "$resume/controller/.root-password.next"
    mv -f "$resume/controller/.root-password.next" "$resume/controller/root-password"
    echo DEVICE_LIFECYCLE_RESUME_REPAIR_APPLIED
  fi
  cat > "$run/peer.ini" <<EOF
[peer]
peer ansible_host=127.0.0.1 ansible_port=$peer_port ansible_user=admin ansible_ssh_private_key_file=$key
EOF
  server_net='set -e; iface=$(ip -o link show | awk -F": " '\''$2 !~ /^(lo|ens3)$/ {print $2; exit}'\''); test -n "$iface"; ip addr replace 192.0.2.1/24 dev "$iface"; ip link set "$iface" up; ip route replace 192.0.2.2/32 dev "$iface"'
  ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$resume_password" --ssh-common-args="$ssh_common" --module-name shell --args "$server_net"
  cat > "$run/server-network-state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
transport=$(ip -o link show | awk -F ': ' '$2 !~ /^(lo|ens3)$/ {print $2; exit}')
printf 'DEVICE_LIFECYCLE_RESUME_SERVER_NETWORK_PRE transport=%s\n' "$transport"
ip -br addr show dev "$transport"
ip route show dev "$transport"
ip route get 192.0.2.2
EOF
  ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$resume_password" --ssh-common-args="$ssh_common" --module-name script --args "$run/server-network-state.sh" | tee -a "$run/network-state.log"
  if test "$reuse_run" = 0; then
    ansible -i "$run/peer.ini" peer --user admin --become --become-method=ansible.builtin.su --become-password-file "$peer_password" --ssh-common-args="$ssh_common" --module-name apt --args 'name=openvpn,wireguard-tools,nftables state=present update_cache=true'
  fi
  manager_resume() {
    local selection=$1
    shift
    PATH="$run/bin:$resume/bin:$PATH" python3 - "$resume_password" "$resume/repo/scripts/bastion-vpn-lifecycle" "$selection" "$@" <<'PY'
import errno, os, pty, select, signal, sys, time
password = open(sys.argv[1], encoding="utf-8").read().strip().encode() + b"\n"
selection = sys.argv[3].encode() + b"\n"
command = [sys.executable, sys.argv[2]] + sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    os.execvpe(command[0], command, os.environ)
sent = False; deadline = time.monotonic() + 60
while True:
    if time.monotonic() > deadline:
        os.kill(pid, signal.SIGTERM); raise SystemExit("resume manager PTY timed out")
    readable, _, _ = select.select([fd], [], [], 1)
    if not readable: continue
    try: output = os.read(fd, 4096)
    except OSError as error:
        if error.errno == errno.EIO: break
        raise
    if not output: break
    if b"assword" in output and not sent:
        os.write(fd, password); sent = True
    if b"Exact device name" in output:
        os.write(fd, selection)
_, result = os.waitpid(pid, 0)
raise SystemExit(os.waitstatus_to_exitcode(result))
PY
  }
  survivor_original="$run/work/profiles/survivor.ovpn"
  if test "$reuse_run" = 1 && ! test -s "$survivor_original" && test -s "$run/survivor.ovpn"; then
    install -m 0600 "$run/survivor.ovpn" "$survivor_original"
  fi
  if ! test -s "$survivor_original"; then
    survivor="resume-$RANDOM"
  manager_resume '' add-open --vpn-host 127.0.0.1 --client "$survivor" --workdir "$run/work" --state-file "$resume/repo/secrets/vpn-authority.yaml"
  manager_resume '' export-open --vpn-host 127.0.0.1 --client "$survivor" --workdir "$run/work" --state-file "$resume/repo/secrets/vpn-authority.yaml"
    install -m 0600 "$run/work/profiles/$survivor.ovpn" "$survivor_original"
  fi
  test -s "$survivor_original"
  transition_nonce=$(printf '%04x%04x' "$RANDOM" "$RANDOM")
  transition_wg="resume-wg-$transition_nonce"
  transition_open="resume-open-$transition_nonce"
  manager_resume '' add-wg --vpn-host 127.0.0.1 --client "$transition_wg" --workdir "$run/work" --state-file "$resume/repo/secrets/vpn-authority.yaml"
  manager_resume '' export-wg --vpn-host 127.0.0.1 --client "$transition_wg" --workdir "$run/work" --state-file "$resume/repo/secrets/vpn-authority.yaml"
  manager_resume '' add-open --vpn-host 127.0.0.1 --client "$transition_open" --workdir "$run/work" --state-file "$resume/repo/secrets/vpn-authority.yaml"
  manager_resume '' export-open --vpn-host 127.0.0.1 --client "$transition_open" --workdir "$run/work" --state-file "$resume/repo/secrets/vpn-authority.yaml"
  transition_wg_original="$run/work/profiles/$transition_wg.conf"
  transition_open_original="$run/work/profiles/$transition_open.ovpn"
  test -s "$transition_wg_original" && test -s "$transition_open_original"
  install -m 0600 "$transition_wg_original" "$run/transition-wg.conf"
  install -m 0600 "$transition_open_original" "$run/transition-open.ovpn"
  install -m 0600 "$survivor_original" "$run/survivor.ovpn"
  install -m 0600 "$run/transition-open.ovpn" "$run/ovpn-a.ovpn"
  install -m 0600 "$run/survivor.ovpn" "$run/ovpn-b.ovpn"
  /usr/bin/scp -F /dev/null -i "$key" -P "$peer_port" $ssh_common "$run/transition-wg.conf" "$run/ovpn-a.ovpn" "$run/ovpn-b.ovpn" admin@127.0.0.1:/tmp/
  cat > "$run/peer-setup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
peer_setup_error() {
  status=$?
  printf 'DEVICE_LIFECYCLE_RESUME_PEER_SETUP_FAIL line=%s status=%s command=%q\n' "$1" "$status" "$BASH_COMMAND" >&2
  ip -br link >&2 || true
  exit "$status"
}
trap 'peer_setup_error "$LINENO"' ERR
for profile in /tmp/ovpn-a.ovpn /tmp/ovpn-b.ovpn; do
  test "$(grep -c '^remote 127.0.0.1 443$' "$profile")" = 1
  sed -i 's/^remote 127\.0\.0\.1 443$/remote 192.0.2.1 443\nroute 192.0.2.1 255.255.255.255 net_gateway/; s/^dev tun$/dev ovpn-a\ndev-type tun/' "$profile"
  grep -qx 'dev-type tun' "$profile"
  grep -qx 'route 192.0.2.1 255.255.255.255 net_gateway' "$profile"
done
sed -i 's/^dev ovpn-a$/dev ovpn-b/' /tmp/ovpn-b.ovpn
install -d -m 0700 /etc/wireguard/bastion-matrix
awk -F ' = ' '/^PrivateKey =/{print $2; exit}' /tmp/transition-wg.conf > /etc/wireguard/bastion-matrix/a.key
awk -F ' = ' '/^PublicKey =/{print $2; exit}' /tmp/transition-wg.conf > /tmp/server-wg.pub
test -s /etc/wireguard/bastion-matrix/a.key; test -s /tmp/server-wg.pub
chmod 0600 /etc/wireguard/bastion-matrix/a.key /tmp/ovpn-a.ovpn /tmp/ovpn-b.ovpn
test -s /tmp/ovpn-a.ovpn && test -s /tmp/ovpn-b.ovpn
transport=$(ip -o link show | awk -F ': ' '$2 !~ /^(lo|ens3)$/ {print $2; exit}')
test -n "$transport"; ip addr replace 192.0.2.2/24 dev "$transport"; ip link set "$transport" up
sysctl -qw net.ipv4.ip_forward=1
nft add table inet bastion_resume
nft 'add chain inet bastion_resume postrouting { type nat hook postrouting priority srcnat; policy accept; }'
nft add rule inet bastion_resume postrouting oifname "$transport" counter masquerade
for spec in 'ovpn-a 12' 'ovpn-b 13'; do
  set -- $spec; ip netns add "$1"; ip link add "$1-r" type veth peer name eth0 netns "$1"
  ip addr add "172.31.$2.1/24" dev "$1-r"; ip link set "$1-r" up
  ip -n "$1" link set lo up; ip -n "$1" addr add "172.31.$2.2/24" dev eth0; ip -n "$1" link set eth0 up
  ip -n "$1" route replace default via "172.31.$2.1"
done
echo "DEVICE_LIFECYCLE_RESUME_PEER_NETWORK_PRE transport=$transport"
ip -br addr show dev "$transport"
ip route show dev "$transport"
ip route get 192.0.2.1
ip -n ovpn-b route get 192.0.2.1 || true
nft list table inet bastion_resume
ip link add wg-resume type wireguard
ip address add 10.43.0.2/32 dev wg-resume
wg set wg-resume private-key /etc/wireguard/bastion-matrix/a.key peer "$(cat /tmp/server-wg.pub)" endpoint 192.0.2.1:443 allowed-ips 10.43.0.1/32 persistent-keepalive 1
ip link set wg-resume up
ip route replace 10.43.0.1/32 dev wg-resume
for _ in $(seq 1 15); do ping -I wg-resume -c 1 -W 1 10.43.0.1 >/dev/null 2>&1 && break; sleep 1; done
ping -I wg-resume -c 1 -W 1 10.43.0.1 >/dev/null
wg show wg-resume latest-handshakes | awk '$2 != 0 { found=1 } END { exit !found }'
echo DEVICE_LIFECYCLE_RESUME_WG_ACTIVE
echo "DEVICE_LIFECYCLE_RESUME_PEER_NETWORK_POST transport=$transport"
ip -n ovpn-b route get 192.0.2.1 || true
nft list table inet bastion_resume
exit 0
EOF
  ansible -i "$run/peer.ini" peer --user admin --become --become-method=ansible.builtin.su --become-password-file "$peer_password" --ssh-common-args="$ssh_common" --module-name script --args "$run/peer-setup.sh" | tee -a "$run/network-state.log"
  peer_probe() {
    local arguments=$1 marker=$2 probe_log
    probe_log=$(mktemp "$run/peer-probe.XXXXXX.log")
    ansible -i "$run/peer.ini" peer --user admin --become --become-method=ansible.builtin.su --become-password-file "$peer_password" --ssh-common-args="$ssh_common" --module-name script --args "$root/tests/vpn-vm-peer-matrix.sh $arguments" | tee "$probe_log"
    rg -q "$marker" "$probe_log"
  }
  peer_probe '--wg-lifecycle-probe available' VPN_VM_WG_LIFECYCLE_TRAFFIC_AVAILABLE
  peer_probe '--openvpn-lifecycle-probe start' VPN_VM_OPENVPN_LIFECYCLE_ACTIVE_A_B
  manager_resume "$transition_wg" revoke-wg --vpn-host 127.0.0.1 --workdir "$run/work" --state-file "$resume/repo/secrets/vpn-authority.yaml"
  cat > "$run/assert-wg-revoked.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if ping -I wg-resume -c 1 -W 2 10.43.0.1 >/dev/null 2>&1; then
  echo 'revoked WireGuard session still carries traffic' >&2
  exit 1
fi
echo DEVICE_LIFECYCLE_RESUME_WG_ACTIVE_SESSION_DENIED
EOF
  ansible -i "$run/peer.ini" peer --user admin --become --become-method=ansible.builtin.su --become-password-file "$peer_password" --ssh-common-args="$ssh_common" --module-name script --args "$run/assert-wg-revoked.sh"
  peer_probe '--wg-lifecycle-probe denied' VPN_VM_WG_LIFECYCLE_TRAFFIC_DENIED
  manager_resume "$transition_open" revoke-open --vpn-host 127.0.0.1 --workdir "$run/work" --state-file "$resume/repo/secrets/vpn-authority.yaml"
  peer_probe '--openvpn-lifecycle-probe teardown' VPN_VM_OPENVPN_REVOKED_A_SESSION_TERMINATED_B_ACTIVE
  peer_probe '--openvpn-lifecycle-probe revoked' VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE
  peer_probe '--openvpn-lifecycle-probe reconnect-b' VPN_VM_OPENVPN_B_RECONNECTED
  ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$resume_password" --ssh-common-args="$ssh_common" --module-name reboot --args 'reboot_timeout=120'
  ANSIBLE_LOCAL_TEMP="$run/ansible" ansible-playbook -i "$run/server.ini" "$resume/repo/playbooks/device-lifecycle-vm.yml" --vault-password-file "$resume/controller/vault-password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$resume_password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common"
  ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$resume_password" --ssh-common-args="$ssh_common" --module-name shell --args "$server_net; systemctl is-active --quiet openvpn-server@bastion.service"
  ANSIBLE_LOCAL_TEMP="$run/ansible-maintenance" ansible-playbook -i "$run/maintenance.ini" "$resume/repo/playbooks/maintenance.yml" --vault-password-file "$resume/controller/vault-password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$resume_password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common"
  ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$resume_password" --ssh-common-args="$ssh_common" --module-name shell --args 'test -s /var/lib/bastion/package-versions.txt'
  ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$resume_password" --ssh-common-args="$ssh_common" --module-name shell --args "$server_net; systemctl is-active --quiet openvpn-server@bastion.service; echo DEVICE_LIFECYCLE_RESUME_MAINTENANCE_TRANSPORT_RESTORED"
  peer_probe '--openvpn-lifecycle-probe reconnect-b' VPN_VM_OPENVPN_B_RECONNECTED
  peer_probe '--openvpn-lifecycle-probe revoked' VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE
  peer_probe '--wg-lifecycle-probe denied' VPN_VM_WG_LIFECYCLE_TRAFFIC_DENIED
  peer_probe '--openvpn-lifecycle-probe reconnect-b' VPN_VM_OPENVPN_B_RECONNECTED
  peer_probe '--openvpn-lifecycle-probe revoked' VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE
  ansible -i "$run/server.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$resume_password" --ssh-common-args="$ssh_common" --module-name shell --args 'systemd-run --no-block --collect --unit=bastion-device-lifecycle-poweroff /usr/bin/systemctl poweroff'
  for _ in $(seq 1 120); do
    if ! kill -0 "$server_pid" 2>/dev/null; then
      wait "$server_pid" 2>/dev/null || true
      server_pid=''
      break
    fi
    sleep 1
  done
  test -z "$server_pid" || { echo 'device-lifecycle resume server did not shut down gracefully' >&2; exit 1; }
  echo DEVICE_LIFECYCLE_RESUME_PASS
  exit
fi

tmp=$(mktemp -d /tmp/bastion-device-lifecycle-vm.XXXXXX)
vm=''
cleanup() {
  status=$?
  forced=0
  if test -n "${vm:-}" && kill -0 "$vm" 2>/dev/null && test -r "$tmp/repo/inventory/device-lifecycle.ini"; then
    ansible -i "$tmp/repo/inventory/device-lifecycle.ini" bastion --user admin --become --become-method=ansible.builtin.su \
      --become-password-file "$tmp/controller/root-password" \
      --ssh-common-args="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes" \
      --module-name shell --args 'sync; systemd-run --no-block --collect --unit=bastion-device-lifecycle-cleanup /usr/bin/systemctl poweroff' >/dev/null 2>&1 || true
    for _ in $(seq 1 120); do
      if ! kill -0 "$vm" 2>/dev/null; then
        wait "$vm" 2>/dev/null || true
        vm=''
        break
      fi
      sleep 1
    done
  fi
  if test -n "${vm:-}"; then
    forced=1
    kill "$vm" 2>/dev/null || true
    wait "$vm" 2>/dev/null || true
    vm=''
  fi
  if test "$forced" = 1; then
    : > "$tmp/.device-lifecycle-resume-unsafe"
    echo 'device-lifecycle VM was force-terminated; retained overlay is unsafe' >&2
  fi
  if test "$BASTION_VPN_VM_KEEP" = 1; then echo "DEVICE_LIFECYCLE_VM_EVIDENCE=$tmp"; else rm -rf "$tmp"; fi
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT
mkdir -p "$tmp/bin" "$tmp/controller"
cp -a "$root" "$tmp/repo"
install_pinned_collections "$tmp/repo" "$tmp/collections"
install -m 0600 "$password" "$tmp/controller/root-password"
vault_password="$tmp/controller/vault-password"
printf '%s\n' synthetic-vault-password > "$vault_password"
chmod 600 "$vault_password"
admin_key=$(<"$key.pub")
root_hash=$(openssl passwd -6 -stdin < "$password")
cat > "$tmp/repo/inventory/secrets-input.json" <<EOF
{"admin_authorized_key":"$admin_key","vault_password_file":"$vault_password","vault_secrets_file":"secrets/server.yaml"}
EOF

if test -n "$wg_deb_cache"; then
  test -r "$wg_deb_cache" || { echo "missing readable BASTION_DEVICE_LIFECYCLE_WG_DEB: $wg_deb_cache" >&2; exit 2; }
  cp "$wg_deb_cache" "$tmp/wg.deb"
else
  curl -fsS --max-time 30 https://archive.ubuntu.com/ubuntu/pool/main/w/wireguard/wireguard-tools_1.0.20250521-1ubuntu1_amd64.deb -o "$tmp/wg.deb"
fi
printf '%s  %s\n' e948f176ea0324252b7f07327becd1d5df14290ef4fafa392a9d41e96b0459c8 "$tmp/wg.deb" | sha256sum --check --status
mkdir "$tmp/wg"
ar p "$tmp/wg.deb" data.tar.zst | zstd -d | bsdtar -x -C "$tmp/wg"
install -m 0755 "$tmp/wg/usr/bin/wg" "$tmp/bin/wg"
"$tmp/bin/wg" genkey > "$tmp/controller/bootstrap-wg.key"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$tmp/controller/bootstrap-openvpn.key" >/dev/null 2>&1
cat > "$tmp/controller/server.yaml" <<EOF
admin-password-hash: $root_hash
root-password-hash: $root_hash
ssh-notify-config: |
  SSHLogFile = /var/log/auth.log
  ServerName = bastion
  TelegramBotToken = synthetic-token
  TelegramNotifyChat = synthetic-chat
EOF
ANSIBLE_LOCAL_TEMP="$tmp/ansible-vault" ansible-vault encrypt --vault-password-file "$vault_password" --output "$tmp/repo/secrets/server.yaml" "$tmp/controller/server.yaml"
rm -f "$tmp/controller/server.yaml" "$tmp/controller/bootstrap-wg.key" "$tmp/controller/bootstrap-openvpn.key"

qemu-img create -f qcow2 -F qcow2 -b "$base" "$tmp/overlay.qcow2" >/dev/null
qemu-img resize "$tmp/overlay.qcow2" 20G >/dev/null
qemu-system-x86_64 -machine accel=tcg -m 2048 -smp 1 -drive "file=$tmp/overlay.qcow2,if=virtio,format=qcow2" -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=n0 -display none -serial "file:$tmp/serial.log" -monitor none >"$tmp/qemu.log" 2>&1 &
vm=$!
sleep 1
if ! kill -0 "$vm" 2>/dev/null; then
  echo "device-lifecycle-vm-test: QEMU failed to start or bind port $port" >&2
  tail -n 40 "$tmp/qemu.log" >&2
  exit 1
fi
sed -E "s/\\[127\\.0\\.0\\.1\\]:[0-9]+/[127.0.0.1]:$port/g" "$known" > "$tmp/repo/inventory/known_hosts"
cat > "$tmp/bin/ssh" <<EOF
#!/usr/bin/env bash
exec /usr/bin/ssh -F /dev/null -i $key -p $port "\$@"
EOF
cat > "$tmp/bin/scp" <<EOF
#!/usr/bin/env bash
exec /usr/bin/scp -F /dev/null -i $key -P $port "\$@"
EOF
chmod 700 "$tmp/bin/ssh" "$tmp/bin/scp"
ssh_args="-F /dev/null -i $key -p $port -o BatchMode=yes -o ConnectTimeout=3 -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes"
for n in $(seq 1 90); do /usr/bin/ssh $ssh_args admin@127.0.0.1 true >/dev/null 2>&1 && break; sleep 1; done
/usr/bin/ssh $ssh_args admin@127.0.0.1 true >/dev/null

cat > "$tmp/repo/playbooks/device-lifecycle-vm.yml" <<'EOF'
---
- hosts: bastion
  remote_user: admin
  become: true
  become_method: ansible.builtin.su
  gather_facts: true
  roles: [secrets_administration, administration, firewall, vpn]
  post_tasks:
    - ansible.builtin.meta: flush_handlers
    - ansible.builtin.import_role:
        name: administration
        tasks_from: root-password
EOF
cat > "$tmp/repo/inventory/device-lifecycle.ini" <<EOF
[bastion]
bastion ansible_host=127.0.0.1 ansible_port=$port ansible_user=admin ansible_ssh_private_key_file=$key admin_authorized_key='$admin_key' netplan_interface=ens3
EOF
ansible -i "$tmp/repo/inventory/device-lifecycle.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp/controller/root-password" --ssh-common-args="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes" --module-name shell --args 'growpart /dev/vda 1 && resize2fs /dev/vda1 && test "$(df --output=avail -k / | tail -n1)" -gt 10485760'

manager() {
  selection=$1
  shift
  PATH="$tmp/bin:$PATH" python3 - "$tmp/controller/root-password" "$tmp/repo/scripts/bastion-vpn-lifecycle" "$selection" "$@" <<'PY'
import errno, os, pty, select, signal, sys, time
password = open(sys.argv[1], encoding="utf-8").read().strip().encode() + b"\n"
selection = sys.argv[3].encode() + b"\n"
command = [sys.executable, sys.argv[2]] + sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    os.execvpe(command[0], command, os.environ)
sent = False
deadline = time.monotonic() + 45
while True:
    if time.monotonic() > deadline:
        os.kill(pid, signal.SIGTERM)
        raise SystemExit("manager PTY timed out")
    readable, _, _ = select.select([fd], [], [], 1)
    if readable:
        try:
            output = os.read(fd, 4096)
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise
        if not output:
            break
        os.write(1, output)
        if b"assword" in output and not sent:
            os.write(fd, password)
            sent = True
        if b"Exact device name" in output:
            os.write(fd, selection)
_, result = os.waitpid(pid, 0)
raise SystemExit(os.waitstatus_to_exitcode(result))
PY
}

set +e
manager '' add-wg --vpn-host 127.0.0.1 --client phone
initial_rc=$?
set -e
test "$initial_rc" = 1 || { echo "expected fresh lifecycle pending rc=1, got $initial_rc" >&2; exit 1; }
test -s "$tmp/repo/secrets/vpn-authority.yaml"
test -s "$tmp/repo/secrets/vpn-server.yaml"
ANSIBLE_LOCAL_TEMP="$tmp/ansible" ansible-playbook -i "$tmp/repo/inventory/device-lifecycle.ini" "$tmp/repo/playbooks/device-lifecycle-vm.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$tmp/controller/root-password" --extra-vars "{\"ansible_ssh_common_args\":\"-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes\"}" --ssh-common-args="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes"
remote_root() {
  ansible -i "$tmp/repo/inventory/device-lifecycle.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp/controller/root-password" --ssh-common-args="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes" --module-name shell --args "$1"
}
remote_root 'test ! -e /var/lib/bastion/secrets/server.yaml; test ! -e /var/lib/bastion/secrets/vpn-server.yaml; test ! -e /var/lib/bastion/age; test -s /run/secrets/bastion/openvpn-server-key; test -s /run/secrets/bastion/wireguard-server-key'
manager '' add-wg --vpn-host 127.0.0.1 --client phone
manager '' add-open --vpn-host 127.0.0.1 --client laptop
manager '' add-open --vpn-host 127.0.0.1 --client survivor
manager '' list-wg --vpn-host 127.0.0.1 | tr -d '\r' | grep -qx phone
manager '' list-open --vpn-host 127.0.0.1 | tr -d '\r' | grep -qx laptop
manager '' list-open --vpn-host 127.0.0.1 | tr -d '\r' | grep -qx survivor
manager '' export-wg --vpn-host 127.0.0.1 --client phone
manager '' export-open --vpn-host 127.0.0.1 --client laptop
manager '' export-open --vpn-host 127.0.0.1 --client survivor
remote_root 'state=$(readlink -f /var/lib/bastion/vpn/current); test "$(find -P "$state" -type f -printf "%f\n" | sort | tr "\n" " ")" = "READY ca.crt crl.pem manifest.sha256 metadata.json peers server.crt "; ! find -P "$state" -type f \( -name "*.key" -o -name "ca.key" \) -print -quit | grep -q .'
phone_public=$(PATH="$tmp/bin:$PATH" python3 - "$tmp/repo/scripts/bastion-vpn-lifecycle" "$tmp/repo/secrets/vpn-authority.yaml" <<'PY'
import importlib.util, sys
from importlib.machinery import SourceFileLoader
spec = importlib.util.spec_from_loader("lifecycle", SourceFileLoader("lifecycle", sys.argv[1]))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
print(module.decrypt(__import__("pathlib").Path(sys.argv[2]))["wireguard"]["clients"]["phone"]["public"])
PY
)
manager phone revoke-wg --vpn-host 127.0.0.1
manager laptop revoke-open --vpn-host 127.0.0.1
remote_root "! wg show wg-bastion peers | grep -Fx '$phone_public'; systemctl is-active --quiet openvpn-server@bastion.service; state=\$(readlink -f /var/lib/bastion/vpn/current); grep -q '\"name\": \"laptop\"' \"\$state/openvpn/metadata.json\"; openssl crl -in \"\$state/openvpn/crl.pem\" -noout -verify -CAfile \"\$state/openvpn/ca.crt\""

# Recovery-specific checks stay inside this disposable VM.  A stale authority
# copy must be refused before decrypt/publish, and server replacement must
# produce a new profile fingerprint while preserving the revoked device.
mkdir -p "$tmp/work"
replacement="$tmp/controller/replacement.json"
recovery_root_password="$tmp/controller/recovery-root-password"
openssl rand -base64 48 > "$recovery_root_password"
chmod 600 "$recovery_root_password"
recovery_root_hash=$(openssl passwd -6 -stdin < "$recovery_root_password")
test "$recovery_root_hash" != "$root_hash"
ROOT_HASH="$root_hash" RECOVERY_ROOT_HASH="$recovery_root_hash" python3 - "$replacement" <<'PY'
import json
import os
import pathlib
import sys

pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "admin-password-hash": os.environ["ROOT_HASH"],
    "root-password-hash": os.environ["RECOVERY_ROOT_HASH"],
    "ssh-notify-config": (
        "SSHLogFile = /var/log/auth.log\n"
        "ServerName = bastion\n"
        "TelegramBotToken = replacement-synthetic-token\n"
        "TelegramNotifyChat = replacement-synthetic-chat\n"
    ),
}), encoding="utf-8")
PY
chmod 600 "$replacement"
stale_state="$tmp/work/stale-authority.yaml"
cp "$tmp/repo/secrets/vpn-authority.yaml" "$stale_state"
set +e
stale_output=$(manager '' recover-fresh --vpn-host 127.0.0.1 --workdir "$tmp/work/stale" --state-file "$stale_state" --replacement-secrets-file "$replacement" 2>&1)
stale_rc=$?
set -e
test "$stale_rc" = 1
printf '%s\n' "$stale_output" | grep -q 'fresh recovery refuses an existing encrypted authority state'
cmp -s "$stale_state" "$tmp/repo/secrets/vpn-authority.yaml"

manager '' export-open --vpn-host 127.0.0.1 --client survivor --workdir "$tmp/work" --state-file "$tmp/repo/secrets/vpn-authority.yaml"
old_profile="$tmp/work/profiles/survivor.ovpn"
old_fingerprint=$(sed -n 's/^peer-fingerprint //p' "$old_profile")
set +e
manager '' replace-server --vpn-host 127.0.0.1 --workdir "$tmp/work" --state-file "$tmp/repo/secrets/vpn-authority.yaml" >"$tmp/work/replace.log" 2>&1
replace_rc=$?
set -e
test "$replace_rc" = 1
ANSIBLE_LOCAL_TEMP="$tmp/ansible-replace" ansible-playbook -i "$tmp/repo/inventory/device-lifecycle.ini" "$tmp/repo/playbooks/device-lifecycle-vm.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$tmp/controller/root-password" --extra-vars "{\"ansible_ssh_common_args\":\"-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes\"}" --ssh-common-args="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes"
manager '' replace-server --vpn-host 127.0.0.1 --workdir "$tmp/work" --state-file "$tmp/repo/secrets/vpn-authority.yaml"
manager '' export-open --vpn-host 127.0.0.1 --client survivor --workdir "$tmp/work" --state-file "$tmp/repo/secrets/vpn-authority.yaml"
new_fingerprint=$(sed -n 's/^peer-fingerprint //p' "$old_profile")
test -n "$old_fingerprint" && test -n "$new_fingerprint" && test "$old_fingerprint" != "$new_fingerprint"
! grep -Fxq "peer-fingerprint $old_fingerprint" "$old_profile"
remote_root "state=\$(readlink -f /var/lib/bastion/vpn/current); grep -q '\"name\": \"survivor\"' \"\$state/openvpn/metadata.json\"; ! grep -q '\"name\": \"laptop\"' \"\$state/openvpn/metadata.json\"; openssl crl -in \"\$state/openvpn/crl.pem\" -noout -verify -CAfile \"\$state/openvpn/ca.crt\""

# Exercise the confirmed-compromise transaction with synthetic replacement
# values; the existing revocation must remain denied after the retry/apply.
set +e
manager '' recover-compromised --vpn-host 127.0.0.1 --workdir "$tmp/work" --state-file "$tmp/repo/secrets/vpn-authority.yaml" --replacement-secrets-file "$replacement" >"$tmp/work/compromise.log" 2>&1
compromise_rc=$?
set -e
test "$compromise_rc" = 1
ANSIBLE_LOCAL_TEMP="$tmp/ansible-compromise" ansible-playbook -i "$tmp/repo/inventory/device-lifecycle.ini" "$tmp/repo/playbooks/device-lifecycle-vm.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$tmp/controller/root-password" --extra-vars "{\"ansible_ssh_common_args\":\"-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes\"}" --ssh-common-args="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes"
install -m 0600 "$recovery_root_password" "$tmp/controller/.root-password.next"
mv -f "$tmp/controller/.root-password.next" "$tmp/controller/root-password"
manager '' recover-compromised --vpn-host 127.0.0.1 --workdir "$tmp/work" --state-file "$tmp/repo/secrets/vpn-authority.yaml" --replacement-secrets-file "$replacement"
remote_root "state=\$(readlink -f /var/lib/bastion/vpn/current); grep -q '\"name\": \"survivor\"' \"\$state/openvpn/metadata.json\"; ! grep -q '\"name\": \"laptop\"' \"\$state/openvpn/metadata.json\"; openssl crl -in \"\$state/openvpn/crl.pem\" -noout -verify -CAfile \"\$state/openvpn/ca.crt\""
ansible -i "$tmp/repo/inventory/device-lifecycle.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp/controller/root-password" --ssh-common-args="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes" --module-name shell --args 'systemd-run --no-block --collect --unit=bastion-device-lifecycle-poweroff /usr/bin/systemctl poweroff'
for _ in $(seq 1 120); do
  if ! kill -0 "$vm" 2>/dev/null; then
    wait "$vm" 2>/dev/null || true
    vm=''
    break
  fi
  sleep 1
done
test -z "$vm" || { echo 'device-lifecycle VM did not shut down gracefully' >&2; exit 1; }
echo DEVICE_LIFECYCLE_VM_PASS
