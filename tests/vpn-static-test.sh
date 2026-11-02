#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

bash -n roles/vpn/files/bastion-vpn-verify-state \
  roles/vpn/files/bastion-vpn-publish-state \
  roles/vpn/files/bastion-vpn-configure-wireguard \
  roles/vpn/files/bastion-vpn-apply-state-once \
  roles/vpn/files/bastion-vpn-apply-state \
  roles/vpn/files/bastion-vpn-cleanup \
  roles/vpn/files/bastion-vpn-stop \
  tests/device-lifecycle-vm-test.sh \
  tests/vpn-vm-test.sh \
  tests/vpn-vm-guest-test.sh \
  tests/vpn-vm-peer-matrix.sh
rg -q 'peer_scp_args=\(.*-P' tests/vpn-vm-test.sh
! rg -q 'hostfwd=udp' tests/vpn-vm-test.sh
! rg -q 'hostfwd=tcp:127.0.0.1:\$openvpn_port-:443' tests/vpn-vm-test.sh
bash tests/vpn-vm-peer-matrix.sh --dns-self-check
bash tests/vpn-vm-peer-matrix.sh --firewall-self-check
tests/vpn-vm-guest-test.sh --admission-self-check
! rg -q -- '--seeded-isolation-after-reload' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -q -- '--seeded-isolation-flows' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -q -- '--seeded-isolation-establish' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -q -- '--seeded-isolation-release' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -F -q 'ct state established,related counter' tests/vpn-vm-test.sh
rg -F -q 'priority mangle' tests/vpn-vm-test.sh
rg -F -q 'nohup ip netns exec "$target_ns" python3' tests/vpn-vm-peer-matrix.sh
rg -F -q 'nohup ip netns exec "$source_ns" python3' tests/vpn-vm-peer-matrix.sh
rg -F -q '"$command" -I FORWARD 1 -i "$input" -o "$output"' tests/vpn-vm-test.sh
rg -F -q '"$command" -D FORWARD -i "$input" -o "$output"' tests/vpn-vm-test.sh
rg -F -q '! "$command" -C FORWARD -i "$input" -o "$output"' tests/vpn-vm-test.sh
rg -F -q 'meta nfproto "$nfproto" "$address_family" saddr "$source" "$address_family" daddr "$target" tcp sport "$sport" tcp dport "$dport"' tests/vpn-vm-test.sh
! rg -F -q 'print $(i + 1); exit' tests/vpn-vm-test.sh
large_counter=$({ printf 'counter packets 7 bytes 1 comment "seeded-large"\n'; seq 1 200000; } | awk -v id='seeded-large' 'index($0, id) { for (i = 1; i <= NF; i++) if ($i == "packets") value = $(i + 1) } END { if (value != "") print value }')
test "$large_counter" = 7
rg -F -q 'VPN_VM_SEEDED_ISOLATION_ESTABLISHED' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -F -q 'VPN_VM_SEEDED_ISOLATION_PEER_PASS' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -F -q 'VPN_VM_SEEDED_ISOLATION_PASS' tests/vpn-vm-test.sh
rg -F -q 'not reply[2] & 0x80' tests/vpn-vm-peer-matrix.sh
rg -F -q 'errno.ECONNREFUSED' tests/vpn-vm-peer-matrix.sh
rg -F -q 'IPv6 2001:db8:100::2 2001:db8:100::1' tests/vpn-vm-peer-matrix.sh
rg -F -q 'IPv4 192.0.2.2 192.0.2.1' tests/vpn-vm-peer-matrix.sh
rg -q 'dual_stack_check wg-a' tests/vpn-vm-peer-matrix.sh
rg -q 'dual_stack_check ovpn-a' tests/vpn-vm-peer-matrix.sh
rg -q 'probe_tcp_listener 192.0.2.1 22' tests/vpn-vm-peer-matrix.sh
rg -q 'probe_tcp_listener 2001:db8:100::1 22' tests/vpn-vm-peer-matrix.sh
rg -q 'probe_tcp_listener 192.0.2.1 443' tests/vpn-vm-peer-matrix.sh
rg -q 'probe_tcp_listener 2001:db8:100::1 443' tests/vpn-vm-peer-matrix.sh
rg -q 'expect_tcp_firewall_drop 192.0.2.1 18082' tests/vpn-vm-peer-matrix.sh
rg -q 'expect_tcp_firewall_drop 2001:db8:100::1 18082' tests/vpn-vm-peer-matrix.sh
rg -q 'VPN_VM_FIREWALL_INGRESS_PASS' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -q "\[2001:db8:100::1\]:443" tests/vpn-vm-peer-matrix.sh
rg -q '2001:db8:100::1/128 via "fd31:\$index::1"' tests/vpn-vm-peer-matrix.sh
rg -q 'VPN_VM_FIREWALL_LISTENER_READY' tests/vpn-vm-test.sh
rg -q 'firewall path and fails immediately if a future service already owns it' tests/vpn-vm-test.sh
rg -F -q 'sysctl -n net.ipv4.ip_forward' tests/vpn-vm-peer-matrix.sh
rg -F -q 'sysctl -n net.ipv6.conf.all.forwarding' tests/vpn-vm-peer-matrix.sh
rg -F -q 'net.ipv4.ip_forward=$ipv4_forward' tests/vpn-vm-peer-matrix.sh
rg -F -q 'net.ipv6.conf.all.forwarding=$ipv6_forward' tests/vpn-vm-peer-matrix.sh
rg -F -q 'rm -f /tmp/bastion-vpn-matrix-dns.py /tmp/bastion-vpn-matrix-tcp.py' tests/vpn-vm-peer-matrix.sh
rg -F -q 'VPN_VM_PEER_MATRIX_FAIL: line %s' tests/vpn-vm-peer-matrix.sh
rg -F -q "trap 'report_error \"\$LINENO\"' ERR" tests/vpn-vm-peer-matrix.sh
rg -F -q 'connection.sendall(f"{family} {local_address} {peer_address}\n".encode())' tests/vpn-vm-peer-matrix.sh
! rg -F -q 'connection.sendall(f"{family} {local_address} {peer_address}\\n".encode())' tests/vpn-vm-peer-matrix.sh

rg -U -q '    - administration\n    - firewall\n    - ssh_notifications\n    - vpn' playbooks/bootstrap.yml
rg -U -q '    - administration\n    - firewall\n    - ssh_notifications\n    - vpn' playbooks/site.yml
rg -A2 'Reapply firewall configuration after maintenance' playbooks/maintenance.yml | rg -q 'name: firewall'
rg -A2 'Reapply VPN configuration after maintenance' playbooks/maintenance.yml | rg -q 'name: vpn'
rg -q 'openvpn-server-key' roles/vpn/templates/bastion.conf.j2
rg -q 'wireguard-server-key' roles/vpn/files/bastion-vpn-configure-wireguard
rg -q 'modprobe wireguard' roles/vpn/files/bastion-vpn-configure-wireguard
rg -F -q 'exec {key_fd}< "$key"' roles/vpn/files/bastion-vpn-configure-wireguard
rg -F -q 'IFS= read -r private_key <&"$key_fd"' roles/vpn/files/bastion-vpn-configure-wireguard
rg -F -q '! IFS= read -r _ <&"$key_fd"' roles/vpn/files/bastion-vpn-configure-wireguard
rg -F -q '[[ "$private_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]' roles/vpn/files/bastion-vpn-configure-wireguard
rg -F -q 'private-key <(printf '\''%s\n'\'' "$private_key")' roles/vpn/files/bastion-vpn-configure-wireguard
! rg -q 'wc -c\|cat "\$key"' roles/vpn/files/bastion-vpn-configure-wireguard

wireguard_test_dir=$(mktemp -d /tmp/bastion-wireguard-key-test.XXXXXX)
trap 'rm -rf "$wireguard_test_dir"' EXIT
wireguard_key=$(printf '%043d=' 0)
mkdir -p "$wireguard_test_dir/bin" "$wireguard_test_dir/state/wireguard"
: > "$wireguard_test_dir/state/wireguard/peers"
sed \
  -e "s#key=/run/secrets/bastion/wireguard-server-key#key=$wireguard_test_dir/key#" \
  -e 's#/usr/sbin/modprobe#modprobe#' \
  roles/vpn/files/bastion-vpn-configure-wireguard > "$wireguard_test_dir/configure-wireguard"
chmod 0700 "$wireguard_test_dir/configure-wireguard"

cat > "$wireguard_test_dir/bin/modprobe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >> "$WG_CALLS"
EOF
cat > "$wireguard_test_dir/bin/ip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1:$2" in
  link:show) exit 1 ;;
  link:add|link:set|address:replace|-6:address) exit 0 ;;
  *) exit 1 ;;
esac
EOF
cat > "$wireguard_test_dir/bin/wg" <<'EOF'
#!/bin/bash
set -euo pipefail
if test "$1" = show; then
  exit 0
fi
test "$1" = set
test "$3" = listen-port
for arg; do
  test "$arg" != "$WG_EXPECTED_KEY"
done
case "$6" in
  /dev/fd/*|/proc/self/fd/*) ;;
  *) exit 1 ;;
esac
test "$(<"$6")" = "$WG_EXPECTED_KEY"
EOF
chmod 0700 "$wireguard_test_dir/bin"/*

run_wireguard_configure() {
  printf '%s' "$1" > "$wireguard_test_dir/key"
  WG_CALLS="$wireguard_test_dir/calls" \
    WG_EXPECTED_KEY="$wireguard_key" \
    PATH="$wireguard_test_dir/bin:$PATH" \
    "$wireguard_test_dir/configure-wireguard" "$wireguard_test_dir/state" \
    > "$wireguard_test_dir/stdout" 2> "$wireguard_test_dir/stderr"
}

: > "$wireguard_test_dir/calls"
run_wireguard_configure "$wireguard_key"
run_wireguard_configure "$wireguard_key"$'\n'
! rg -F -q "$wireguard_key" "$wireguard_test_dir/stdout" "$wireguard_test_dir/stderr" "$wireguard_test_dir/calls"

expect_wireguard_rejection() {
  : > "$wireguard_test_dir/calls"
  set +e
  run_wireguard_configure "$1"
  status=$?
  set -e
  test "$status" -ne 0
  test ! -s "$wireguard_test_dir/calls"
}

expect_wireguard_rejection "${wireguard_key%=}A"
expect_wireguard_rejection "${wireguard_key:0:22}"$'\n'"${wireguard_key:22}"
rg -q '^proto tcp-server$' roles/vpn/templates/bastion.conf.j2
rg -q '^port 443$' roles/vpn/templates/bastion.conf.j2
rg -q 'listen-port 443' roles/vpn/files/bastion-vpn-configure-wireguard
rg -q '^data-ciphers AES-256-GCM:AES-128-GCM$' roles/vpn/templates/bastion.conf.j2
rg -q '^auth SHA256$' roles/vpn/templates/bastion.conf.j2
rg -q '^allow-compression no$' roles/vpn/templates/bastion.conf.j2
! rg -n 'tls-crypt( |$)' roles/vpn
rg -q 'redirect-gateway def1 ipv6' roles/vpn/templates/bastion.conf.j2
dns_lines=$(rg -n 'dhcp-option DNS' roles/vpn/templates/bastion.conf.j2 | cut -d: -f1 | tr '\n' ' ')
set -- $dns_lines
[ "$1" -lt "$2" ]
rg -q '1.1.1.1' roles/vpn/templates/bastion.conf.j2
rg -q '8.8.8.8' roles/vpn/templates/bastion.conf.j2
rg -q 'net.ipv4.ip_forward = 1' roles/vpn/tasks/main.yml
rg -q 'net.ipv6.conf.all.forwarding = 1' roles/vpn/tasks/main.yml
rg -q 'community.general' collections/requirements.yml
rg -q '13.5.0' collections/requirements.yml
rg -F -q 'install_pinned_collections "$resume/repo" "$run/collections"' tests/device-lifecycle-vm-test.sh
rg -F -q 'install_pinned_collections "$tmp/repo" "$tmp/collections"' tests/device-lifecycle-vm-test.sh
rg -F -q 'ansible-galaxy collection install -r "$repo/collections/requirements.yml" -p "$destination" --force' tests/device-lifecycle-vm-test.sh
rg -F -q 'export ANSIBLE_COLLECTIONS_PATH="$destination"' tests/device-lifecycle-vm-test.sh
python3 tests/firewall-direct-policy-test.py
python3 tests/firewall-ufw-ip6tables-test.py
ban_probe_keygen_line=$(rg -n 'ssh-keygen -q -t ed25519 -N' tests/vpn-vm-test.sh | cut -d: -f1)
server_scp_args_line=$(rg -n '^server_scp_args=' tests/vpn-vm-test.sh | cut -d: -f1)
peer_scp_args_line=$(rg -n '^peer_scp_args=' tests/vpn-vm-test.sh | cut -d: -f1)
ban_probe_copy_line=$(rg -n 'scp "\$\{server_scp_args\[@\]\}" "\$tmp_root/ban-probe-key\.pub"' tests/vpn-vm-test.sh | cut -d: -f1)
peer_key_copy_line=$(rg -n 'scp "\$\{peer_scp_args\[@\]\}" "\$tmp_root/ban-probe-key" ' tests/vpn-vm-test.sh | cut -d: -f1)
baseline_probe_line=$(rg -n -- '--ssh-ban-probe available' tests/vpn-vm-test.sh | cut -d: -f1)
ban_action_line=$(rg -n 'fail2ban-client set sshd banip 192\.0\.2\.2' tests/vpn-vm-test.sh | cut -d: -f1)
denied_probe_line=$(rg -n -- '--ssh-ban-probe banned' tests/vpn-vm-test.sh | cut -d: -f1)
[ "$ban_probe_keygen_line" -lt "$ban_probe_copy_line" ]
[ "$server_scp_args_line" -lt "$ban_probe_copy_line" ]
[ "$peer_scp_args_line" -lt "$peer_key_copy_line" ]
[ "$peer_key_copy_line" -lt "$baseline_probe_line" ]
[ "$ban_probe_copy_line" -lt "$baseline_probe_line" ]
[ "$baseline_probe_line" -lt "$ban_action_line" ]
[ "$ban_action_line" -lt "$denied_probe_line" ]
rg -q 'netdev=peer0,mac=52:54:00:12:34:57' tests/vpn-vm-test.sh
rg -q 'netdev=peer0,mac=52:54:00:12:34:58' tests/vpn-vm-test.sh
rg -q 'ip -6 neigh replace 2001:db8:100::2 lladdr 52:54:00:12:34:58' tests/vpn-vm-test.sh
rg -q 'ip -6 neigh replace 2001:db8:100::1 lladdr 52:54:00:12:34:57' tests/vpn-vm-test.sh
! test -e roles/vpn/templates/90-bastion-vpn.nft.j2
! test -e roles/vpn/templates/bastion-nftables.service.j2
rg -q '^Requires=bastion-secrets.service ufw.service$' roles/vpn/templates/bastion-vpn-apply.service.j2
rg -q '^After=bastion-secrets.service ufw.service network-online.target$' roles/vpn/templates/bastion-vpn-apply.service.j2
! rg -q 'bastion-vpn-renew-crl' roles/vpn/files roles/vpn/templates Makefile
rg -q 'Remove obsolete VPS CRL signer units' roles/vpn/tasks/main.yml
rg -q 'Require a long-lived controller CRL before signer cleanup' roles/vpn/tasks/main.yml
rg -q 'Require verified published VPN state before signer cleanup' roles/vpn/tasks/main.yml
rg -q 'Check for legacy VPS CRL signer artifacts' roles/vpn/tasks/main.yml
rg -q 'vpn_legacy_signer_present' roles/vpn/tasks/main.yml
rg -q 'Remove obsolete persistent OpenVPN CA key after controller CRL activation' roles/vpn/tasks/main.yml
rg -q 'Check obsolete VPS CRL signer unit presence' roles/vpn/tasks/main.yml
! rg -q 'failed_when: false' roles/vpn/tasks/main.yml
! rg -q 'Remove obsolete persistent OpenVPN CA key' roles/secrets_administration/tasks/main.yml
controller_check_line=$(rg -n 'Require a long-lived controller CRL before signer cleanup' roles/vpn/tasks/main.yml | cut -d: -f1)
ca_cleanup_line=$(rg -n 'Remove obsolete persistent OpenVPN CA key after controller CRL activation' roles/vpn/tasks/main.yml | cut -d: -f1)
signer_cleanup_line=$(rg -n 'Check obsolete VPS CRL signer unit presence' roles/vpn/tasks/main.yml | cut -d: -f1)
test "$controller_check_line" -lt "$ca_cleanup_line"
test "$ca_cleanup_line" -lt "$signer_cleanup_line"
rg -A10 'Require verified published VPN state before signer cleanup' roles/vpn/tasks/main.yml | rg -F -q 'vpn_state_verification.rc | default(1) == 0'
rg -A10 'Require verified published VPN state before signer cleanup' roles/vpn/tasks/main.yml | rg -q 'when: vpn_legacy_signer_present'
test "$(rg -c 'vpn_long_lived_crl.rc | default(1) == 0' roles/vpn/tasks/main.yml)" -ge 4
rg -q 'publisher refused CRL sequence rollback' roles/vpn/files/bastion-vpn-publish-state
rg -q 'Requires=bastion-secrets.service' roles/vpn/tasks/main.yml roles/vpn/templates/bastion-vpn-apply.service.j2
rg -q '^BindsTo=bastion-secrets.service$' roles/vpn/templates/bastion-vpn-apply.service.j2
rg -q '^ExecStopPost=/usr/local/libexec/bastion-vpn-cleanup$' roles/vpn/templates/bastion-vpn-apply.service.j2
rg -q '^ExecStopPost=/usr/local/libexec/bastion-vpn-cleanup$' roles/vpn/templates/bastion-secrets-vpn-cleanup.conf.j2
rg -q 'Clean VPN runtime state when secrets stop' roles/vpn/tasks/main.yml
! rg -q 'bastion-vpn-apply.service' roles/vpn/files/bastion-vpn-cleanup
rg -q 'flock' roles/vpn/files/bastion-vpn-verify-state roles/vpn/files/bastion-vpn-apply-state-once
rg -q 'realpath -e' roles/vpn/files/bastion-vpn-verify-state
rg -q '/run/bastion-vpn/active' roles/vpn/templates/bastion.conf.j2 roles/vpn/tasks/main.yml
! rg -q '/var/lib/bastion/vpn/current/openvpn' roles/vpn/templates/bastion.conf.j2
rg -q 'fail_closed' roles/vpn/files/bastion-vpn-apply-state-once
rg -q 'notify: Validate and restart OpenVPN' roles/vpn/tasks/main.yml
rg -q 'bastion-vpn-verify-state' roles/vpn/handlers/main.yml
rg -q 'Restart OpenVPN after validated configuration change' roles/vpn/handlers/main.yml
rg -A1 'Restart OpenVPN after validated configuration change' roles/vpn/handlers/main.yml | rg -q 'listen: Validate and restart OpenVPN'
rg -q 'Stop active VPN listeners when public state is absent' roles/vpn/tasks/main.yml
rg -q 'Reject absent public VPN state with active listeners' roles/vpn/tasks/main.yml
rg -q 'VPN_VM_MISSING_CURRENT_STOPPED' tests/vpn-vm-guest-test.sh
rg -q 'invalid or expired CRL' roles/vpn/files/bastion-vpn-verify-state
rg -q 'openssl crl .* -CAfile' roles/vpn/files/bastion-vpn-verify-state
rg -q 'lacks owner read permission' roles/vpn/files/bastion-vpn-verify-state
rg -q 'sha256sum --strict --check' roles/vpn/files/bastion-vpn-verify-state
rg -F -q -- "-printf '%P\\n'" roles/vpn/files/bastion-vpn-verify-state
! rg -F -q -- "-printf '%P\\\\n'" roles/vpn/files/bastion-vpn-verify-state
rg -q 'bastion-vpn-stop' roles/vpn/files/bastion-vpn-apply-state roles/vpn/tasks/main.yml
rg -q 'Reject invalid published VPN state' roles/vpn/tasks/main.yml
! rg -n 'ca.key\|client.key\|wg genkey' tests/vpn-vm-guest-test.sh
rg -q 'forged' tests/vpn-vm-guest-test.sh tests/vpn-vm-test.sh
rg -q 'reject_crl_release missing' tests/vpn-vm-guest-test.sh
rg -q 'reject_crl_release unreadable' tests/vpn-vm-guest-test.sh
rg -q 'reject_crl_release invalid' tests/vpn-vm-guest-test.sh
rg -q 'reject_crl_release expired' tests/vpn-vm-guest-test.sh
rg -q 'assert_openvpn_runtime_reader' tests/vpn-vm-guest-test.sh
rg -q 'assert_no_openvpn_admission' tests/vpn-vm-guest-test.sh
rg -q 'systemctl status bastion-vpn-apply.service' tests/vpn-vm-guest-test.sh
rg -q 'journalctl -u bastion-vpn-apply.service' tests/vpn-vm-guest-test.sh
rg -q 'explicit-apply-stop' tests/vpn-vm-guest-test.sh
rg -q 'reject-secrets-restart' tests/vpn-vm-guest-test.sh
rg -q -- '--wg-lifecycle-probe' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -q 'VPN_VM_WG_LIFECYCLE_TRAFFIC_DENIED' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -q 'openvpn-lifecycle-probe' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -q 'VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -q 'VPN_VM_OPENVPN_B_RECONNECTED' tests/vpn-vm-peer-matrix.sh tests/vpn-vm-test.sh
rg -q 'openssl ca .* -revoke' tests/vpn-vm-test.sh
rg -q 'releases/revoked' tests/vpn-vm-test.sh
rg -q 'VPN_VM_WG_LIFECYCLE_FAILED_START_CLEANUP_PASS' tests/vpn-vm-test.sh
rg -q 'non-reentrant stop-post cleanup' tests/vpn-vm-test.sh
rg -q '^dev-type tun$' tests/vpn-vm-test.sh
rg -q 'ip netns pids "\$ns"' tests/vpn-vm-peer-matrix.sh
rg -q 'kill -KILL "\$pid"' tests/vpn-vm-peer-matrix.sh
! rg -q 'pkill' tests/vpn-vm-peer-matrix.sh
rg -F -q 'END { print transport }' tests/vpn-vm-peer-matrix.sh
rg -q 'peer-root-material.sh' tests/vpn-vm-test.sh
rg -q 'chown root:root "\$path"' tests/vpn-vm-test.sh
rg -q 'chmod 0600 "\$path"' tests/vpn-vm-test.sh
rg -q '/etc/wireguard/bastion-matrix/a.key' tests/vpn-vm-test.sh tests/vpn-vm-peer-matrix.sh
rg -q '/etc/wireguard/bastion-matrix/b.key' tests/vpn-vm-test.sh tests/vpn-vm-peer-matrix.sh
! rg -q 'setup_wg .* /tmp/wg-client' tests/vpn-vm-peer-matrix.sh
rg -q 'VPN_VM_PEER_MATRIX_FAIL: peer isolation breach' tests/vpn-vm-peer-matrix.sh
rg -q 'idempotent-reapply.log' tests/vpn-vm-test.sh
rg -q 'changed=0.*failed=0' tests/vpn-vm-test.sh
! rg -q 'rg -Eq' tests/vpn-vm-test.sh
printf '%s\n' 'bastion : ok=42 changed=2 unreachable=0 failed=0' | rg -q 'bastion[[:space:]]*:.*changed=[1-9].*failed=0'
printf '%s\n' 'bastion : ok=42 changed=0 unreachable=0 failed=0' | rg -q 'bastion[[:space:]]*:.*changed=0.*failed=0'
rg -q 'unchanged reapply restarted OpenVPN' tests/vpn-vm-test.sh
rg -q 'changed OpenVPN config did not restart OpenVPN' tests/vpn-vm-test.sh
rg -q 'OPENVPN_ACTIVE_ENTER=' tests/vpn-vm-test.sh
rg -q 'openvpn_active_enter()' tests/vpn-vm-test.sh
rg -q 'bastion_openvpn_verb' roles/vpn/tasks/main.yml roles/vpn/templates/bastion.conf.j2 tests/vpn-vm-test.sh
! rg -in 'client.*private\|ca.*private' roles/vpn playbooks inventory
! rg -n -e '^[^#].*(peer|client).*(=|:)' inventory/hosts.ini.example roles/vpn/templates

python3 -m py_compile scripts/bastion-vpn-lifecycle tests/device-lifecycle-test.py
python3 tests/device-lifecycle-test.py
rg -q 'bastion-vpn-publish-state' roles/vpn/tasks/main.yml
rg -q 'StrictHostKeyChecking=yes' scripts/bastion-vpn-lifecycle
rg -q 'UserKnownHostsFile=' scripts/bastion-vpn-lifecycle
rg -q 'vault_password_file' scripts/bastion-vpn-lifecycle inventory/secrets-input.json.example
rg -q 'ansible-vault' scripts/bastion-vpn-lifecycle
! rg -qi 'sops\|owner_age_recipient\|vps_age' scripts/bastion-vpn-lifecycle
rg -q 'openssl", "ca".*"-revoke"' scripts/bastion-vpn-lifecycle
rg -q 'openssl", "ca".*"-gencrl"' scripts/bastion-vpn-lifecycle
rg -q 'peer-fingerprint' scripts/bastion-vpn-lifecycle
rg -q '0.0.0.0/0, ::/0' scripts/bastion-vpn-lifecycle
rg -q 'VPN server certificate does not match its runtime private key' roles/vpn/files/bastion-vpn-verify-state
for target in vpn-add-wg vpn-add-open vpn-list-wg vpn-list-open vpn-export-wg vpn-export-open vpn-revoke-wg vpn-revoke-open vpn-migrate-open; do
  make --no-print-directory -n "$target" VPN_HOST=vpn.example CLIENT=device >/dev/null
done
rg -A2 '^vpn-migrate-open:' Makefile | rg -q 'migrate-crl --vpn-host'
! rg -q '^vpn-.*HOST' Makefile
