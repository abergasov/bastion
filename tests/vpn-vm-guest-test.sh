#!/usr/bin/env bash
set -euo pipefail

fixture_states=${1:?public fixture state directory is required}
fail() { echo "VPN_VM_ASSERT_FAIL: $1" >&2; exit 1; }
stage() { echo "VPN_VM_STAGE: $1"; }
assert_active() {
  local name=$1
  systemctl is-active --quiet "$name" || fail "$name is not active"
}
assert_inactive() {
  local name=$1
  systemctl is-active --quiet "$name" && fail "$name unexpectedly active"
  return 0
}
assert_no_iface() {
  local name=$1
  ip link show "$name" >/dev/null 2>&1 && fail "$name unexpectedly exists"
  return 0
}
wait_for_listener() {
  local command=$1
  for _ in $(seq 1 20); do
    "$command" && return 0
    sleep 0.1
  done
  return 1
}
tcp_443_listener() { ss -ltnH '( sport = :443 )' | grep -q .; }
udp_443_listener() { ss -lunH '( sport = :443 )' | grep -q .; }
assert_openvpn_runtime_reader() {
  local pid user
  pid=$(systemctl show --property=MainPID --value openvpn-server@bastion.service)
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || fail 'OpenVPN has no main PID'
  user=$(ps -o user= -p "$pid" | tr -d '[:space:]')
  test "$user" = root || fail "OpenVPN runtime reader is $user, not root"
}
assert_no_openvpn_admission() {
  assert_inactive openvpn-server@bastion.service
  if tcp_443_listener; then
    fail 'OpenVPN TCP/443 admission listener is still active'
  fi
}
if test "$fixture_states" = --admission-self-check; then
  assert_inactive() { :; }
  tcp_443_listener() { return 1; }
  assert_no_openvpn_admission
  tcp_443_listener() { return 0; }
  if (assert_no_openvpn_admission) >/dev/null 2>&1; then
    fail 'admission assertion accepted a listener'
  fi
  echo VPN_VM_ADMISSION_ASSERT_PASS
  exit 0
fi

if test "$fixture_states" = --firewall-runtime-check; then
  fail2ban_client=$(command -v fail2ban-client || true)
  test -n "$fail2ban_client" || fail 'fail2ban-client is unavailable'
  ufw status | grep -E '^Status: active$' >/dev/null || fail 'UFW is not active'
  ufw reload >/dev/null || fail 'UFW reload failed'
  ufw status | grep -E '^Status: active$' >/dev/null || fail 'UFW is inactive after reload'
  ufw show raw | grep -F 'ufw-before-forward' >/dev/null || fail 'UFW raw chains are missing'
  iptables-save | grep -E -- '-A POSTROUTING .*10\.42\.0\.0/24.*MASQUERADE' >/dev/null || fail 'IPv4 VPN NAT is missing'
  iptables-save | grep -E -- '-A POSTROUTING .*10\.43\.0\.0/24.*MASQUERADE' >/dev/null || fail 'IPv4 WireGuard NAT is missing'
  ip6tables-save | grep -F 'ufw6-before-forward' >/dev/null || fail 'IPv6 UFW raw chains are missing'
  $fail2ban_client status sshd >/dev/null || fail 'fail2ban sshd jail is not active'
  $fail2ban_client get sshd actions | grep -E 'nftables|iptables|ufw' >/dev/null || fail 'fail2ban sshd jail has no firewall action'
  printf '%s\n' '2026-11-01T00:00:00 bastion sshd[1]: Failed password for invalid user test from 198.51.100.77 port 22 ssh2' > /tmp/bastion-fail2ban-fixture.log
  printf '%s\n' '2026-11-01T00:00:01 bastion sshd[1]: Failed password for invalid user test from 2001:db8::77 port 22 ssh2' >> /tmp/bastion-fail2ban-fixture.log
  fail2ban-regex /tmp/bastion-fail2ban-fixture.log sshd | grep -F '2 matched' >/dev/null || fail 'fail2ban sshd filter did not match both synthetic families'
  rm -f /tmp/bastion-fail2ban-fixture.log
  for address in 198.51.100.77 2001:db8::77; do
    $fail2ban_client set sshd banip "$address" >/dev/null
    $fail2ban_client get sshd banip | grep -F "$address" >/dev/null || fail "fail2ban did not ban $address"
    $fail2ban_client set sshd unbanip "$address" >/dev/null
    if $fail2ban_client get sshd banip | grep -F "$address" >/dev/null; then fail "fail2ban did not unban $address"; fi
  done
  echo VPN_VM_FIREWALL_RUNTIME_PASS
  exit 0
fi

test -d "$fixture_states" || fail "fixture state directory is missing"
if test "${2:-}" = assert-stopped; then
  stage missing-current-stop
  assert_inactive bastion-vpn-apply.service
  assert_inactive openvpn-server@bastion.service
  assert_no_iface wg-bastion
  echo VPN_VM_MISSING_CURRENT_STOPPED
  exit 0
fi
fixture=$(mktemp -d /tmp/bastion-vpn-fixture.XXXXXX)
trap 'rm -rf "$fixture"' EXIT

install -d -m 0700 /var/lib/bastion/vpn/releases
stage install-fixture-releases
for release in valid forged expired invalid missing unreadable; do
  test -d "$fixture_states/$release"
  rm -rf "/var/lib/bastion/vpn/releases/$release"
  cp -a "$fixture_states/$release" "/var/lib/bastion/vpn/releases/$release"
  chown -R root:root "/var/lib/bastion/vpn/releases/$release"
  chmod -R go-w "/var/lib/bastion/vpn/releases/$release"
done

ln -sfn releases/valid /var/lib/bastion/vpn/current.next
mv -Tf /var/lib/bastion/vpn/current.next /var/lib/bastion/vpn/current
stage apply-valid-release
/usr/local/libexec/bastion-vpn-verify-state >/dev/null
if ! /usr/local/libexec/bastion-vpn-apply-state; then
  systemctl status bastion-vpn-apply.service --no-pager || true
  journalctl -u bastion-vpn-apply.service -n 100 --no-pager || true
  ip link show wg-bastion || true
  exit 1
fi
assert_active bastion-vpn-apply.service
assert_active openvpn-server@bastion.service
assert_openvpn_runtime_reader
if ! wait_for_listener tcp_443_listener; then
  ss -ltnp || true
  systemctl status openvpn-server@bastion.service --no-pager || true
  journalctl -u openvpn-server@bastion.service -n 100 --no-pager || true
  fail 'TCP 443 listener is missing after 2 seconds'
fi
wait_for_listener udp_443_listener || fail 'UDP 443 listener is missing after 2 seconds'

stage explicit-apply-stop
systemctl stop bastion-vpn-apply.service
assert_inactive bastion-vpn-apply.service
assert_inactive openvpn-server@bastion.service
assert_no_iface wg-bastion
stage restore-after-apply-stop
/usr/local/libexec/bastion-vpn-apply-state
assert_active bastion-vpn-apply.service
assert_active openvpn-server@bastion.service

stage reject-secrets-restart
cp /var/lib/bastion/secrets/openvpn-server-key "$fixture/openvpn-server-key"
printf 'invalid synthetic key\n' > /var/lib/bastion/secrets/openvpn-server-key
if systemctl restart bastion-secrets.service; then fail 'invalid persistent VPN key restart unexpectedly succeeded'; fi
assert_inactive bastion-vpn-apply.service
assert_inactive openvpn-server@bastion.service
assert_no_iface wg-bastion
install -m 0600 "$fixture/openvpn-server-key" /var/lib/bastion/secrets/openvpn-server-key
systemctl restart bastion-secrets.service
stage restore-after-secrets-restart
/usr/local/libexec/bastion-vpn-apply-state
assert_active bastion-vpn-apply.service
assert_active openvpn-server@bastion.service

reject_crl_release() {
  local release=$1
  ln -sfn "releases/$release" /var/lib/bastion/vpn/current.next
  mv -Tf /var/lib/bastion/vpn/current.next /var/lib/bastion/vpn/current
  stage "reject-$release-crl"
  if /usr/local/libexec/bastion-vpn-verify-state; then fail "$release CRL unexpectedly verified"; fi
  if /usr/local/libexec/bastion-vpn-apply-state; then fail "$release CRL apply unexpectedly succeeded"; fi
  assert_no_openvpn_admission
  assert_no_iface wg-bastion
}

rm /var/lib/bastion/vpn/releases/missing/openvpn/crl.pem
chmod 000 /var/lib/bastion/vpn/releases/unreadable/openvpn/crl.pem
reject_crl_release missing
reject_crl_release unreadable
reject_crl_release invalid
# The CRL parses and is future-dated, but this signer is not the public CA.
reject_crl_release forged
reject_crl_release expired

ln -sfn releases/valid /var/lib/bastion/vpn/current.next
mv -Tf /var/lib/bastion/vpn/current.next /var/lib/bastion/vpn/current
stage restore-valid-release
systemctl restart bastion-vpn-apply.service

# OpenVPN must keep using the consumer-pinned release, even when a publisher
# replaces current after activation.
ln -sfn releases/forged /var/lib/bastion/vpn/current.next
mv -Tf /var/lib/bastion/vpn/current.next /var/lib/bastion/vpn/current
stage replace-current-after-activation
systemctl restart openvpn-server@bastion.service
assert_active openvpn-server@bastion.service
ip link show wg-bastion >/dev/null

# A later apply with a missing runtime key must tear down the still-active
# OpenVPN listener and WireGuard interface instead of preserving old access.
ln -sfn releases/valid /var/lib/bastion/vpn/current.next
mv -Tf /var/lib/bastion/vpn/current.next /var/lib/bastion/vpn/current
stage reject-missing-runtime-key
mv /run/secrets/bastion/wireguard-server-key "$fixture/wireguard-server-key"
if /usr/local/libexec/bastion-vpn-apply-state; then fail 'apply unexpectedly succeeded without WG key'; fi
assert_inactive openvpn-server@bastion.service
assert_no_iface wg-bastion
mv "$fixture/wireguard-server-key" /run/secrets/bastion/wireguard-server-key
stage restore-runtime-key
systemctl restart bastion-vpn-apply.service
assert_active bastion-vpn-apply.service
assert_active openvpn-server@bastion.service

# The harness re-applies the role after this marker. It must stop then reject
# these listeners rather than treating an absent current pointer as initial setup.
rm -f /var/lib/bastion/vpn/current
stage missing-current-marker
echo VPN_VM_FIXTURE_PASS
