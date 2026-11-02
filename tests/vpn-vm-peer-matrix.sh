#!/usr/bin/env bash
set -euo pipefail

# Runs only as root in the disposable peer VM. Its root namespace is a
# synthetic internet for four isolated client namespaces.
if test "${1:-}" = --dns-self-check; then
  python3 - <<'PY'
import io

def validate(query, reply):
    question = query[12:]
    if (len(reply) < 12 + len(question) or reply[:2] != query[:2]
            or not reply[2] & 0x80 or reply[3] & 0x0f
            or reply[12:12 + len(question)] != question):
        raise ValueError("synthetic DNS response is invalid")


query = b"\x42\x42\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x04test\x00\x00\x01\x00\x01"
reply = query[:2] + b"\x81\x80" + query[4:6] + b"\x00\x00\x00\x00\x00\x00" + query[12:]
validate(query, reply)
for invalid in (
    reply[:11],
    query,
    b"\x42\x43" + reply[2:],
    reply[:3] + b"\x83" + reply[4:],
    reply[:-1] + b"x",
):
    try:
        validate(query, invalid)
    except ValueError:
        continue
    raise SystemExit("synthetic DNS self-check accepted an invalid response")

expected_tcp_reply = "IPv6 2001:db8:100::2 2001:db8:100::1"
tcp_reply = f"{expected_tcp_reply}\n".encode()
if io.BytesIO(tcp_reply).readline().decode().strip() != expected_tcp_reply:
    raise SystemExit("synthetic TCP response is invalid")
PY
  exit
fi

if test "${1:-}" = --firewall-self-check; then
  python3 - <<'PY'
import errno
import socket

def firewall_rejected(error):
    return isinstance(error, TimeoutError)

if not firewall_rejected(socket.timeout()):
    raise SystemExit("firewall self-check did not accept a timeout")
if firewall_rejected(ConnectionRefusedError(errno.ECONNREFUSED, "refused")):
    raise SystemExit("firewall self-check accepted a closed-port refusal")
PY
  exit
fi

seeded_state=/tmp/bastion-vpn-seeded-isolation
seeded_flows="$seeded_state/flows"
seeded_failure=/tmp/bastion-vpn-seeded-isolation.failure
seeded_lifecycle=/tmp/bastion-vpn-seeded-isolation.lifecycle

seeded_cleanup() {
  test -r "$seeded_state/pids" || { rm -rf "$seeded_state"; return; }
  while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$seeded_state/pids"
  sleep 0.1
  while read -r pid; do kill -KILL "$pid" 2>/dev/null || true; done < "$seeded_state/pids"
  rm -rf "$seeded_state"
}

if test "${1:-}" = --seeded-isolation-flows; then
  for ns in wg-a wg-b ovpn-a ovpn-b; do
    ip netns show | grep -E "^$ns" >/dev/null || { echo "missing namespace $ns" >&2; exit 1; }
  done
  install -d -m 0700 "$seeded_state"
  ovpn_a4=$(ip -n ovpn-a -o -4 addr show dev ovpn-a scope global | awk '{ print $4 }' | cut -d/ -f1)
  ovpn_a6=$(ip -n ovpn-a -o -6 addr show dev ovpn-a scope global | awk '{ print $4 }' | cut -d/ -f1)
  ovpn_b4=$(ip -n ovpn-b -o -4 addr show dev ovpn-b scope global | awk '{ print $4 }' | cut -d/ -f1)
  ovpn_b6=$(ip -n ovpn-b -o -6 addr show dev ovpn-b scope global | awk '{ print $4 }' | cut -d/ -f1)
  cat > "$seeded_flows" <<EOF
wg-wg 4 wg-a wg-b 10.43.0.2 10.43.0.3 24001 25001
wg-wg 6 wg-a wg-b fd42:2::2 fd42:2::3 24002 25002
ovpn-ovpn 4 ovpn-a ovpn-b $ovpn_a4 $ovpn_b4 24003 25003
ovpn-ovpn 6 ovpn-a ovpn-b $ovpn_a6 $ovpn_b6 24004 25004
wg-ovpn 4 wg-a ovpn-b 10.43.0.2 $ovpn_b4 24005 25005
wg-ovpn 6 wg-a ovpn-b fd42:2::2 $ovpn_b6 24006 25006
ovpn-wg 4 ovpn-a wg-b $ovpn_a4 10.43.0.3 24007 25007
ovpn-wg 6 ovpn-a wg-b $ovpn_a6 fd42:2::3 24008 25008
EOF
  awk 'NF == 8 && ($2 == "4" || $2 == "6") && $7 ~ /^[0-9]+$/ && $8 ~ /^[0-9]+$/ { next } { exit 1 } END { exit NR == 8 ? 0 : 1 }' "$seeded_flows"
  echo VPN_VM_SEEDED_ISOLATION_FLOWS_READY
  exit
fi

if test "${1:-}" = --seeded-isolation-establish; then
  test -r "$seeded_flows" || { echo 'seeded flow manifest is missing' >&2; exit 1; }
  rm -f "$seeded_failure"
  rm -f "$seeded_lifecycle"
  rm -f "$seeded_state/release"
  rm -rf "$seeded_state/ready" "$seeded_state/result"
  install -d -m 0700 "$seeded_state/ready" "$seeded_state/result"
  : > "$seeded_state/pids"
  while read -r name family source_ns target_ns source target sport dport; do
    id="$name-$family"
    nohup ip netns exec "$target_ns" python3 - "$family" "$target" "$dport" >"$seeded_state/$id-server.log" 2>&1 </dev/null <<'PY' &
import socket
import sys

family, address, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
sock = socket.socket(socket.AF_INET6 if family == "6" else socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind((address, port))
sock.listen(1)
connection, _ = sock.accept()
with connection:
    if connection.recv(32) != b"seeded":
        raise SystemExit("seeded TCP request was invalid")
    connection.sendall(b"seeded-ok")
    if connection.recv(32) == b"after-release":
        connection.sendall(b"isolation-breach")
PY
    echo $! >> "$seeded_state/pids"
    nohup ip netns exec "$source_ns" python3 - "$family" "$source" "$target" "$sport" "$dport" "$seeded_state/ready/$id" "$seeded_state/release" "$seeded_state/result/$id" >"$seeded_state/$id-client.log" 2>&1 </dev/null <<'PY' &
import socket
import sys
import time

family, source, target, sport, dport, ready, release, result = sys.argv[1:]
sock = socket.socket(socket.AF_INET6 if family == "6" else socket.AF_INET, socket.SOCK_STREAM)
try:
    sock.settimeout(1)
    sock.bind((source, int(sport)))
    for _ in range(30):
        try:
            sock.connect((target, int(dport)))
            break
        except OSError:
            time.sleep(.1)
    else:
        raise TimeoutError("seeded connection did not establish")
    sock.sendall(b"seeded")
    if sock.recv(32) != b"seeded-ok":
        raise RuntimeError("seeded data did not round-trip")
    open(ready, "w").close()
    for _ in range(300):
        if __import__("os").path.exists(release):
            break
        time.sleep(.1)
    else:
        raise TimeoutError("release signal did not arrive")
    sock.settimeout(3)
    sock.sendall(b"after-release")
    try:
        reply = sock.recv(32)
    except TimeoutError:
        reply = b""
    if reply:
        raise RuntimeError("post-release TCP data was delivered")
    open(result, "w").write("pass\n")
except BaseException as error:
    open(result, "w").write(f"fail: {error!r}\n")
    with open("/tmp/bastion-vpn-seeded-isolation.failure", "a") as failure:
        failure.write(f"{source}->{target}:{sport}->{dport}: {error!r}\n")
finally:
    sock.close()
PY
    echo $! >> "$seeded_state/pids"
  done < "$seeded_flows"
  for id in wg-wg-4 wg-wg-6 ovpn-ovpn-4 ovpn-ovpn-6 wg-ovpn-4 wg-ovpn-6 ovpn-wg-4 ovpn-wg-6; do
    for _ in $(seq 1 50); do test -e "$seeded_state/ready/$id" && break; sleep 0.1; done
    test -e "$seeded_state/ready/$id" || {
      test -r "$seeded_state/result/$id" && cat "$seeded_state/result/$id" >&2 || true
      seeded_cleanup
      echo "seeded TCP flow did not become ready: $id" >&2
      exit 1
    }
  done
  echo VPN_VM_SEEDED_ISOLATION_ESTABLISHED
  exit
fi

if test "${1:-}" = --seeded-isolation-release; then
  test -r "$seeded_flows" || { echo 'seeded flow manifest is missing' >&2; exit 1; }
  while read -r pid; do
    if kill -0 "$pid" 2>/dev/null; then echo "before-release pid=$pid alive"; else echo "before-release pid=$pid dead"; fi
  done < "$seeded_state/pids" | tee -a "$seeded_lifecycle"
  : > "$seeded_state/release"
  for id in wg-wg-4 wg-wg-6 ovpn-ovpn-4 ovpn-ovpn-6 wg-ovpn-4 wg-ovpn-6 ovpn-wg-4 ovpn-wg-6; do
    for _ in $(seq 1 300); do test -e "$seeded_state/result/$id" && break; sleep 0.1; done
    if ! test -e "$seeded_state/result/$id"; then
      while read -r pid; do
        if kill -0 "$pid" 2>/dev/null; then echo "missing-result pid=$pid alive"; else echo "missing-result pid=$pid dead"; fi
      done < "$seeded_state/pids" | tee -a "$seeded_lifecycle"
      echo "seeded isolation result did not complete: $id" >&2
      exit 1
    fi
    test "$(cat "$seeded_state/result/$id")" = pass || { echo "seeded isolation was not enforced: $id" >&2; exit 1; }
  done
  echo VPN_VM_SEEDED_ISOLATION_PEER_PASS
  exit
fi

if test "${1:-}" = --seeded-isolation-cleanup; then
  seeded_cleanup
  exit
fi

if test "${1:-}" = --ssh-ban-probe; then
  action=${2:?ssh ban probe action is required}
  ssh_args=(-F /dev/null -i /tmp/ban-probe-key -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
  check_connection() {
    local source=$1 destination=$2
    case "$action" in
      banned)
        if ssh "${ssh_args[@]}" -o BindAddress="$source" admin@"$destination" true >/dev/null 2>&1; then
          echo "SSH unexpectedly succeeded from $source while banned" >&2
          exit 1
        fi
        ;;
      available|unbanned)
        ssh "${ssh_args[@]}" -o BindAddress="$source" admin@"$destination" true >/dev/null
        ;;
      *)
        echo "unsupported ssh ban probe action: $action" >&2
        exit 2
        ;;
    esac
  }
  check_connection 192.0.2.2 192.0.2.1
  check_connection 2001:db8:100::2 2001:db8:100::1
  case "$action" in
    available) echo VPN_VM_FAIL2BAN_SSH_BASELINE ;;
    banned) echo VPN_VM_FAIL2BAN_SSH_DENIED ;;
    unbanned) echo VPN_VM_FAIL2BAN_SSH_RESTORED ;;
  esac
  exit
fi

# The controller invokes this focused probe between server lifecycle actions.
# It uses the same synthetic key material as the matrix, but one client is
# enough to prove an actual WireGuard data path is present or absent.
if test "${1:-}" = --wg-lifecycle-probe; then
  expected=${2:?expected result (available or denied) is required}
  interface=wg-lifecycle

  cleanup_lifecycle_probe() {
    ip link delete "$interface" 2>/dev/null || true
  }
  trap cleanup_lifecycle_probe EXIT

  test -r /etc/wireguard/bastion-matrix/a.key
  test -r /tmp/server-wg.pub
  ip link add "$interface" type wireguard
  ip address add 10.43.0.2/32 dev "$interface"
  wg set "$interface" \
    private-key /etc/wireguard/bastion-matrix/a.key \
    peer "$(cat /tmp/server-wg.pub)" \
    endpoint 192.0.2.1:443 \
    allowed-ips 10.43.0.1/32 \
    persistent-keepalive 1
  ip link set up dev "$interface"
  ip route replace 10.43.0.1/32 dev "$interface"

  case "$expected" in
    available)
      # A failed secrets restart deliberately defers local recovery for up to
      # 30 seconds so the preceding denied probe cannot race it.
      for _ in $(seq 1 45); do
        ping -c 1 -W 1 10.43.0.1 >/dev/null 2>&1 && break
        sleep 1
      done
      ping -c 1 -W 1 10.43.0.1 >/dev/null
      wg show "$interface" latest-handshakes | awk '$2 != 0 { found=1 } END { exit !found }'
      echo VPN_VM_WG_LIFECYCLE_TRAFFIC_AVAILABLE
      ;;
    denied)
      if ping -c 1 -W 2 10.43.0.1 >/dev/null 2>&1; then
        echo 'VPN_VM_WG_LIFECYCLE_FAIL: traffic remained available' >&2
        exit 1
      fi
      wg show "$interface" latest-handshakes | awk '$2 == 0 { found=1 } END { exit !found }'
      echo VPN_VM_WG_LIFECYCLE_TRAFFIC_DENIED
      ;;
    *)
      echo "VPN_VM_WG_LIFECYCLE_FAIL: unsupported expected result $expected" >&2
      exit 2
      ;;
  esac
  exit
fi

# Controlled OpenVPN lifecycle probe.  The peer VM is the only place that
# receives these client profiles; the VPS release remains public-only.
require_openvpn_profile() {
  local profile=$1
  if ! test -f "$profile" || ! test -r "$profile" || ! test -s "$profile"; then
    printf 'VPN_VM_OPENVPN_LIFECYCLE_FAIL: required client profile is missing or unreadable: %s\n' "$profile" >&2
    return 1
  fi
}

if test "${1:-}" = --openvpn-lifecycle-probe-config-self-check; then
  temporary=$(mktemp -d)
  trap 'rm -rf "$temporary"' EXIT
  if require_openvpn_profile "$temporary/ovpn-a.ovpn" >/dev/null 2>&1; then
    echo 'OpenVPN lifecycle config self-check accepted a missing profile' >&2
    exit 1
  fi
  : > "$temporary/ovpn-a.ovpn"
  if require_openvpn_profile "$temporary/ovpn-a.ovpn" >/dev/null 2>&1; then
    echo 'OpenVPN lifecycle config self-check accepted an empty profile' >&2
    exit 1
  fi
  printf 'client\n' > "$temporary/ovpn-a.ovpn"
  require_openvpn_profile "$temporary/ovpn-a.ovpn"
  echo VPN_VM_OPENVPN_LIFECYCLE_PROFILE_GUARD_PASS
  exit
fi

if test "${1:-}" = --openvpn-lifecycle-probe; then
  action=${2:?OpenVPN lifecycle action is required}
  start_client() {
    local name=$1 profile=$2
    rm -f "/tmp/$name.log"
    ip netns exec "$name" openvpn --config "$profile" --log "/tmp/$name.log" --writepid "/tmp/$name.pid" --daemon "$name"
    for _ in $(seq 1 30); do ip -n "$name" link show "$name" >/dev/null 2>&1 && return 0; sleep 1; done
    printf 'OpenVPN client %s did not create its TUN device; recent log follows\n' "$name" >&2
    tail -80 "/tmp/$name.log" >&2 || true
    return 1
  }
  stop_client() {
    local name=$1 pid='' stopped=0
    if test -r "/tmp/$name.pid"; then
      pid=$(cat "/tmp/$name.pid")
      kill "$pid" 2>/dev/null || true
      for _ in $(seq 1 30); do
        if ! kill -0 "$pid" 2>/dev/null; then stopped=1; break; fi
        sleep 1
      done
      if test "$stopped" != 1; then
        printf 'OpenVPN client %s did not stop before reconnect; recent log follows\n' "$name" >&2
        tail -80 "/tmp/$name.log" >&2 || true
        return 1
      fi
    fi
    ip -n "$name" link delete "$name" 2>/dev/null || true
    for _ in $(seq 1 30); do
      ! ip -n "$name" link show "$name" >/dev/null 2>&1 && return 0
      sleep 1
    done
    printf 'OpenVPN client %s TUN device remained after daemon stop\n' "$name" >&2
    return 1
  }
  wait_for_openvpn_listener() {
    for _ in $(seq 1 30); do
      if ip netns exec ovpn-b python3 - <<'PY'
import socket
sock = socket.create_connection(("192.0.2.1", 443), timeout=1)
sock.close()
PY
      then return 0; fi
      sleep 1
    done
    echo 'OpenVPN TCP listener was not reachable before survivor reconnect' >&2
    return 1
  }
  case "$action" in
    start)
      require_openvpn_profile /tmp/ovpn-a.ovpn
      require_openvpn_profile /tmp/ovpn-b.ovpn
      start_client ovpn-a /tmp/ovpn-a.ovpn
      start_client ovpn-b /tmp/ovpn-b.ovpn
      echo VPN_VM_OPENVPN_LIFECYCLE_ACTIVE_A_B
      ;;
    teardown)
      require_openvpn_profile /tmp/ovpn-a.ovpn
      require_openvpn_profile /tmp/ovpn-b.ovpn
      for _ in $(seq 1 30); do
        if ! ip -n ovpn-a link show ovpn-a >/dev/null 2>&1; then
          ip netns exec ovpn-b ping -c 1 -W 2 10.42.0.1 >/dev/null
          echo VPN_VM_OPENVPN_REVOKED_A_SESSION_TERMINATED_B_ACTIVE
          exit
        fi
        sleep 1
      done
      echo 'revoked OpenVPN session remained active after server restart' >&2
      exit 1
      ;;
    revoked)
      require_openvpn_profile /tmp/ovpn-a.ovpn
      require_openvpn_profile /tmp/ovpn-b.ovpn
      # Stop the pre-restart session, then make a fresh connection attempt with
      # the revoked profile.  A daemon may keep retrying, so admission is the
      # bounded absence of a TUN device, not merely its process exit status.
      for pid in $(ip netns pids ovpn-a 2>/dev/null); do kill "$pid" 2>/dev/null || true; done
      ip -n ovpn-a link delete ovpn-a 2>/dev/null || true
      ip netns exec ovpn-a openvpn --config /tmp/ovpn-a.ovpn --writepid /tmp/ovpn-a.pid --daemon ovpn-a-revoked || true
      for _ in $(seq 1 30); do
        if ip -n ovpn-a link show ovpn-a >/dev/null 2>&1; then
          echo 'revoked OpenVPN profile created a tunnel during its denial window' >&2
          exit 1
        fi
        sleep 1
      done
      test -r /tmp/ovpn-a.pid && kill "$(cat /tmp/ovpn-a.pid)" 2>/dev/null || true
      ip netns exec ovpn-b ping -c 1 -W 2 10.42.0.1 >/dev/null
      echo VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE
      ;;
    reconnect-b)
      require_openvpn_profile /tmp/ovpn-b.ovpn
      wait_for_openvpn_listener
      stop_client ovpn-b
      start_client ovpn-b /tmp/ovpn-b.ovpn
      ip netns exec ovpn-b ping -c 1 -W 2 10.42.0.1 >/dev/null
      echo VPN_VM_OPENVPN_B_RECONNECTED
      ;;
    *) echo "unsupported OpenVPN lifecycle action: $action" >&2; exit 2 ;;
  esac
  exit
fi

namespaces=(wg-a wg-b ovpn-a ovpn-b)
transport=$(ip -o link show | awk -F': ' '$2 !~ /^(lo|ens3)$/ && !transport { transport = $2 } END { print transport }')
test -n "$transport"
dns_pid=''
tcp_pid=''
ipv4_forward=''
ipv6_forward=''
ipv4_forward_read=0
ipv6_forward_read=0

probe_tcp_listener() {
  local address=$1 port=$2 timeout=${3:-3}
  python3 - "$address" "$port" "$timeout" <<'PY'
import socket
import sys

address, port, timeout = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
family = socket.AF_INET6 if ':' in address else socket.AF_INET
sock = socket.socket(family, socket.SOCK_STREAM)
sock.settimeout(timeout)
try:
    sock.connect((address, port))
finally:
    sock.close()
PY
}

wait_for_tcp_listener() {
  local name=$1
  shift
  for _ in $(seq 1 20); do
    "$@" 0.1 >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  printf 'VPN_VM_PEER_MATRIX_FAIL: %s did not accept TCP before readiness retries were exhausted\n' "$name" >&2
  "$@"
}

expect_tcp_firewall_drop() {
  local address=$1 port=$2
  python3 - "$address" "$port" <<'PY'
import errno
import socket
import sys

address, port = sys.argv[1], int(sys.argv[2])
family = socket.AF_INET6 if ':' in address else socket.AF_INET
sock = socket.socket(family, socket.SOCK_STREAM)
sock.settimeout(3)
try:
    sock.connect((address, port))
except TimeoutError:
    pass
except OSError as error:
    if error.errno == errno.ECONNREFUSED:
        raise SystemExit("temporary listener was closed instead of rejected by the firewall")
    raise SystemExit(f"unexpected rejected-port result: {error!r}")
else:
    raise SystemExit("firewall allowed a new connection to the temporary listener")
finally:
    sock.close()
PY
}

# The server fixture starts this listener on both families. A timeout proves the
# input policy rejected a new connection; a closed port would only prove absence.
wait_for_tcp_listener 'SSH IPv4' probe_tcp_listener 192.0.2.1 22
wait_for_tcp_listener 'SSH IPv6' probe_tcp_listener 2001:db8:100::1 22
wait_for_tcp_listener 'OpenVPN TCP/443 IPv4' probe_tcp_listener 192.0.2.1 443
# This reaches the IPv6-only fixture, proving only the TCP/443 firewall path;
# it is not an OpenVPN IPv6 admission check.
wait_for_tcp_listener 'TCP/443 IPv6 firewall fixture' probe_tcp_listener 2001:db8:100::1 443
expect_tcp_firewall_drop 192.0.2.1 18082
expect_tcp_firewall_drop 2001:db8:100::1 18082
echo VPN_VM_FIREWALL_INGRESS_PASS

report_error() {
  local status=$?
  printf 'VPN_VM_PEER_MATRIX_FAIL: line %s\n' "$1" >&2
  exit "$status"
}

cleanup() {
  test -z "$dns_pid" || kill "$dns_pid" 2>/dev/null || true
  test -z "$tcp_pid" || kill "$tcp_pid" 2>/dev/null || true
  rm -f /tmp/bastion-vpn-matrix-dns.py /tmp/bastion-vpn-matrix-tcp.py
  if test -f /tmp/bastion-vpn-keep-namespaces; then
    return
  fi
  nft delete table inet bastion_vpn_matrix 2>/dev/null || true
  for ns in "${namespaces[@]}"; do
    for pid in $(ip netns pids "$ns" 2>/dev/null); do kill "$pid" 2>/dev/null || true; done
    sleep 0.1
    for pid in $(ip netns pids "$ns" 2>/dev/null); do kill -KILL "$pid" 2>/dev/null || true; done
  done
  for ns in "${namespaces[@]}"; do ip netns del "$ns" 2>/dev/null || true; done
  test "$ipv4_forward_read" -eq 0 || sysctl -qw "net.ipv4.ip_forward=$ipv4_forward" || true
  test "$ipv6_forward_read" -eq 0 || sysctl -qw "net.ipv6.conf.all.forwarding=$ipv6_forward" || true
}
trap 'report_error "$LINENO"' ERR
trap cleanup EXIT

if ipv4_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null); then ipv4_forward_read=1; fi
if ipv6_forward=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null); then ipv6_forward_read=1; fi
sysctl -qw net.ipv4.ip_forward=1
sysctl -qw net.ipv6.conf.all.forwarding=1
nft add table inet bastion_vpn_matrix
nft 'add chain inet bastion_vpn_matrix forward { type filter hook forward priority 0; policy accept; }'
nft 'add chain inet bastion_vpn_matrix postrouting { type nat hook postrouting priority srcnat; policy accept; }'
nft add rule inet bastion_vpn_matrix postrouting oifname "$transport" masquerade

add_peer() {
  local ns=$1 index=$2
  ip netns add "$ns"
  ip link add "$ns-r" type veth peer name eth0 netns "$ns"
  ip addr add "172.31.$index.1/24" dev "$ns-r"
  ip -6 addr add "fd31:$index::1/64" dev "$ns-r"
  ip link set "$ns-r" up
  ip -n "$ns" link set lo up
  ip -n "$ns" addr add "172.31.$index.2/24" dev eth0
  ip -n "$ns" -6 addr add "fd31:$index::2/64" dev eth0
  ip -n "$ns" link set eth0 up
  ip -n "$ns" route replace default via "172.31.$index.1"
  ip -n "$ns" -6 route replace default via "fd31:$index::1"
}
add_peer wg-a 10
add_peer wg-b 11
add_peer ovpn-a 12
add_peer ovpn-b 13

cat >/tmp/bastion-vpn-matrix-dns.py <<'PY'
import selectors
import socket

selector = selectors.DefaultSelector()
for family, address in ((socket.AF_INET, "192.0.2.2"), (socket.AF_INET6, "2001:db8:100::2")):
    sock = socket.socket(family, socket.SOCK_DGRAM)
    sock.bind((address, 53))
    sock.setblocking(False)
    selector.register(sock, selectors.EVENT_READ)
while True:
    for key, _ in selector.select():
        data, peer = key.fileobj.recvfrom(4096)
        if len(data) >= 12:
            reply = data[:2] + b"\x81\x80" + data[4:6] + b"\x00\x00\x00\x00\x00\x00" + data[12:]
            key.fileobj.sendto(reply, peer)
PY
python3 /tmp/bastion-vpn-matrix-dns.py &
dns_pid=$!

cat >/tmp/bastion-vpn-matrix-tcp.py <<'PY'
import selectors
import socket

selector = selectors.DefaultSelector()
# The first port is dual-stack; the second deliberately has no IPv6 listener
# so the controlled client receives ECONNREFUSED before trying IPv4.
for family, address, port in (
    (socket.AF_INET, "192.0.2.2", 18080),
    (socket.AF_INET6, "2001:db8:100::2", 18080),
    (socket.AF_INET, "192.0.2.2", 18081),
):
    listener = socket.socket(family, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if family == socket.AF_INET6:
        listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    listener.bind((address, port))
    listener.listen()
    listener.setblocking(False)
    selector.register(listener, selectors.EVENT_READ)

while True:
    for key, _ in selector.select():
        connection, _ = key.fileobj.accept()
        family = "IPv6" if connection.family == socket.AF_INET6 else "IPv4"
        local_address = connection.getsockname()[0]
        peer_address = connection.getpeername()[0]
        connection.sendall(f"{family} {local_address} {peer_address}\n".encode())
        connection.close()
PY
python3 /tmp/bastion-vpn-matrix-tcp.py &
tcp_pid=$!

dns_check() {
  local ns=$1 address=$2
  ip netns exec "$ns" python3 - "$address" <<'PY'
import socket
import sys
address = sys.argv[1]
family = socket.AF_INET6 if ':' in address else socket.AF_INET
query = b'\x42\x42\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x04test\x00\x00\x01\x00\x01'
sock = socket.socket(family, socket.SOCK_DGRAM)
sock.settimeout(3)
sock.sendto(query, (address, 53))
reply, _ = sock.recvfrom(4096)
question = query[12:]
if (len(reply) < 12 + len(question) or reply[:2] != query[:2]
        or not reply[2] & 0x80 or reply[3] & 0x0f
        or reply[12:12 + len(question)] != question):
    raise SystemExit('synthetic DNS response is invalid')
PY
}

dual_stack_check() {
  local ns=$1
  ip netns exec "$ns" python3 - <<'PY'
import errno
import socket

v4 = "192.0.2.2"
v6 = "2001:db8:100::2"

def connect(family, address, port):
    sock = socket.socket(family, socket.SOCK_STREAM)
    sock.settimeout(3)
    try:
        sock.connect((address, port))
        return sock.makefile("rb").readline().decode().strip()
    finally:
        sock.close()

ipv6_reply = connect(socket.AF_INET6, v6, 18080)
if ipv6_reply != "IPv6 2001:db8:100::2 2001:db8:100::1":
    raise SystemExit(f"dual-stack responder did not confirm IPv6 egress through the VPS: {ipv6_reply!r}")

try:
    connect(socket.AF_INET6, v6, 18081)
except OSError as error:
    if error.errno != errno.ECONNREFUSED:
        raise SystemExit(f"IPv6 fallback endpoint failed with {error!r}, expected refusal")
else:
    raise SystemExit("IPv6 fallback endpoint unexpectedly accepted a connection")

ipv4_reply = connect(socket.AF_INET, v4, 18081)
if ipv4_reply != "IPv4 192.0.2.2 192.0.2.1":
    raise SystemExit(f"dual-stack responder did not confirm IPv4 fallback through the VPS: {ipv4_reply!r}")
PY
}

setup_wg() {
  local ns=$1 interface=$2 ipv4=$3 ipv6=$4 key=$5 index=$6 endpoint=$7
  ip -n "$ns" link add "$interface" type wireguard
  ip -n "$ns" addr add "$ipv4/32" dev "$interface"
  ip -n "$ns" -6 addr add "$ipv6/128" dev "$interface"
  ip -n "$ns" route replace 192.0.2.1/32 via "172.31.$index.1"
  ip -n "$ns" -6 route replace 2001:db8:100::1/128 via "fd31:$index::1"
  ip netns exec "$ns" wg set "$interface" private-key "$key" peer "$(cat /tmp/server-wg.pub)" endpoint "$endpoint" allowed-ips 0.0.0.0/0,::/0 persistent-keepalive 1
  ip -n "$ns" link set "$interface" up
  ip -n "$ns" route replace default dev "$interface"
  ip -n "$ns" -6 route replace default dev "$interface"
}
setup_wg wg-a wg-a 10.43.0.2 fd42:2::2 /etc/wireguard/bastion-matrix/a.key 10 192.0.2.1:443
setup_wg wg-b wg-b 10.43.0.3 fd42:2::3 /etc/wireguard/bastion-matrix/b.key 11 '[2001:db8:100::1]:443'
for ns in wg-a wg-b; do
  for _ in $(seq 1 15); do
    ip netns exec "$ns" wg show "$ns" latest-handshakes | awk '$2 != 0 { found=1 } END { exit !found }' && break
    sleep 1
  done
  ip netns exec "$ns" wg show "$ns" latest-handshakes | awk '$2 != 0 { found=1 } END { exit !found }'
done

ip netns exec ovpn-a openvpn --config /tmp/ovpn-a.ovpn --daemon ovpn-a
ip netns exec ovpn-b openvpn --config /tmp/ovpn-b.ovpn --daemon ovpn-b
for ns in ovpn-a ovpn-b; do
  for _ in $(seq 1 30); do ip -n "$ns" link show "$ns" >/dev/null 2>&1 && break; sleep 1; done
  ip -n "$ns" link show "$ns" >/dev/null
done

ping4() { ip netns exec "$1" ping -c 1 -W 2 "$2" >/dev/null; }
ping6() { ip netns exec "$1" ping -6 -c 1 -W 2 "$2" >/dev/null; }
expect_blocked() {
  local source=$1 target=$2 family=$3 address=$4
  if "ping$family" "$source" "$address"; then
    echo "VPN_VM_PEER_MATRIX_FAIL: peer isolation breach $source->$target IPv$family" >&2
    exit 1
  fi
}
for ns in wg-a wg-b; do
  ping4 "$ns" 10.43.0.1; ping6 "$ns" fd42:2::1
  ping4 "$ns" 192.0.2.2; ping6 "$ns" 2001:db8:100::2
  dns_check "$ns" 192.0.2.2; dns_check "$ns" 2001:db8:100::2
done
for ns in ovpn-a ovpn-b; do
  ping4 "$ns" 10.42.0.1; ping6 "$ns" fd42:1::1
  ping4 "$ns" 192.0.2.2; ping6 "$ns" 2001:db8:100::2
  dns_check "$ns" 192.0.2.2; dns_check "$ns" 2001:db8:100::2
done
dual_stack_check wg-a
dual_stack_check ovpn-a
grep -q 'dhcp-option DNS 1.1.1.1' /tmp/ovpn-a.log
grep -q 'dhcp-option DNS 8.8.8.8' /tmp/ovpn-a.log

ovpn_b4=$(ip -n ovpn-b -o -4 addr show dev ovpn-b scope global | awk '{ print $4 }' | cut -d/ -f1)
ovpn_b6=$(ip -n ovpn-b -o -6 addr show dev ovpn-b scope global | awk '{ print $4 }' | cut -d/ -f1)
expect_blocked wg-a wg-b 4 10.43.0.3
expect_blocked wg-a wg-b 6 fd42:2::3
expect_blocked ovpn-a ovpn-b 4 "$ovpn_b4"
expect_blocked ovpn-a ovpn-b 6 "$ovpn_b6"
expect_blocked wg-a ovpn-b 4 "$ovpn_b4"
expect_blocked wg-a ovpn-b 6 "$ovpn_b6"
expect_blocked ovpn-a wg-b 4 10.43.0.3
expect_blocked ovpn-a wg-b 6 fd42:2::3

echo VPN_VM_PEER_MATRIX_PASS
