#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
fake_bin="$tmp_dir/bin"
mkdir "$fake_bin"

cat > "$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = -o ] && [ "$2" = BatchMode=yes ]
[ "$3" = -o ] && [ "$4" = GlobalKnownHostsFile=/dev/null ]
[ "$5" = -o ] && [[ "$6" == UserKnownHostsFile=* ]]
[ "$7" = -o ] && [ "$8" = StrictHostKeyChecking=yes ]
printf '%s\n' "$*" >> "$SSH_CALLS"
case "${10}" in
  'cat /etc/os-release')
    if [ "${CASE}" = unsupported_os ]; then printf 'ID=debian\nVERSION_ID="12"\n'; else printf 'ID=ubuntu\nVERSION_ID="26.04"\n'; fi ;;
  'id -u')
    [ "${CASE}" = insufficient_privileges ] && printf '1000\n' || printf '0\n' ;;
  'sudo -n true') [ "${CASE}" != insufficient_privileges ] ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/ssh"

write_inventory() {
  cat > "$tmp_dir/hosts.ini" <<'EOF'
[bootstrap]
bastion ansible_host=8.8.8.8 ansible_user=root netplan_interface=ens3 ipv4_address=8.8.8.8 ipv4_prefix=32 ipv4_gateway=8.8.8.1 ipv6_address=2001:4860:4860::8888 ipv6_prefix=64 ipv6_gateway=fe80::1 dns_servers='["1.1.1.1","2606:4700:4700::1111"]'

[bastion_admin]
bastion
EOF
  printf '%s\n' '8.8.8.8 ssh-ed25519 ZmFrZQ==' > "$tmp_dir/known_hosts"
}

run_failure() {
  local name=$1
  : > "$tmp_dir/calls"
  rm -f "$tmp_dir/provisioned"
  if PATH="$fake_bin:$PATH" SSH_CALLS="$tmp_dir/calls" CASE="$name" "$root_dir/scripts/preflight-bastion" "$tmp_dir/hosts.ini" "$tmp_dir/known_hosts"; then
    return 1
  fi
  [ ! -e "$tmp_dir/provisioned" ]
}

write_inventory
sed -i 's/ipv4_prefix=32/ipv4_prefix=not-a-prefix/' "$tmp_dir/hosts.ini"
run_failure invalid_input

write_inventory
printf '%s\n' '8.8.4.4 ssh-ed25519 ZmFrZQ==' > "$tmp_dir/known_hosts"
run_failure wrong_host_key
[ ! -s "$tmp_dir/calls" ]

write_inventory
run_failure unsupported_os
[ "$(wc -l < "$tmp_dir/calls")" = 1 ]

write_inventory
run_failure insufficient_privileges
[ "$(wc -l < "$tmp_dir/calls")" = 3 ]

write_inventory
sed -i 's/ipv4_gateway=8.8.8.1/ipv4_gateway=192.0.2.1/' "$tmp_dir/hosts.ini"
: > "$tmp_dir/calls"
PATH="$fake_bin:$PATH" SSH_CALLS="$tmp_dir/calls" CASE=valid_private_gateway "$root_dir/scripts/preflight-bastion" "$tmp_dir/hosts.ini" "$tmp_dir/known_hosts"
[ "$(wc -l < "$tmp_dir/calls")" = 2 ]

write_inventory
sed -i "s@dns_servers=.*@dns_servers='[]'@" "$tmp_dir/hosts.ini"
run_failure empty_dns_servers
[ ! -s "$tmp_dir/calls" ]

write_inventory
sed -i "s@dns_servers=.*@dns_servers='[\"192.0.2.53\"]'@" "$tmp_dir/hosts.ini"
: > "$tmp_dir/calls"
PATH="$fake_bin:$PATH" SSH_CALLS="$tmp_dir/calls" CASE=private_dns_server "$root_dir/scripts/preflight-bastion" "$tmp_dir/hosts.ini" "$tmp_dir/known_hosts"
[ "$(wc -l < "$tmp_dir/calls")" = 2 ]

write_inventory
sed -i "s@dns_servers=.*@dns_servers='[\"0.0.0.0\"]'@" "$tmp_dir/hosts.ini"
run_failure unspecified_dns_server
[ ! -s "$tmp_dir/calls" ]

write_inventory
sed -i "s@dns_servers=.*@dns_servers='[\"224.0.0.1\"]'@" "$tmp_dir/hosts.ini"
run_failure multicast_dns_server
[ ! -s "$tmp_dir/calls" ]
