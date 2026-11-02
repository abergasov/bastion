#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d /tmp/bastion-runtime-secrets-test.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT
persistent="$tmp_dir/persistent"
runtime_parent="$tmp_dir/runtime-parent"
runtime="$runtime_parent/bastion"
mkdir -p "$persistent" "$runtime_parent"
chmod 0700 "$persistent" "$runtime_parent"
for name in admin-password-hash root-password-hash; do
  printf '$6$synthetic$hash\n' > "$persistent/$name"
done
cat > "$persistent/ssh-notify.conf" <<'EOF'
SSHLogFile = /var/log/auth.log
ServerName = bastion
TelegramBotToken = synthetic-token
TelegramNotifyChat = synthetic-chat
EOF
openssl genpkey -algorithm ED25519 -out "$persistent/openvpn-server-key" >/dev/null 2>&1
openssl genpkey -algorithm ED25519 -out "$persistent/openvpn-ca-key" >/dev/null 2>&1
printf '%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' > "$persistent/wireguard-server-key"
chmod 0600 "$persistent"/*
sed -e "s#/var/lib/bastion/secrets#$persistent#g" \
    -e "s#/run/secrets/bastion#$runtime#g" \
    -e "s#/run/secrets#$runtime_parent#g" \
    -e 's/ -o root -g root//g' \
    "$root_dir/roles/secrets_administration/templates/bastion-decrypt-secrets.sh.j2" > "$tmp_dir/activate"
chmod 0700 "$tmp_dir/activate"
"$tmp_dir/activate"
test -L "$runtime"
test "$(stat -c %a "$runtime_parent")" = 700
test "$(stat -Lc %a "$runtime")" = 700
for name in admin-password-hash root-password-hash ssh-notify.conf openvpn-server-key openvpn-ca-key wireguard-server-key; do
  test -s "$runtime/$name"
  test "$(stat -c %a "$runtime/$name")" = 600
done
test ! -e "$runtime_parent/openvpn-ca-key"
test "$(find "$runtime_parent" -type f -name openvpn-ca-key -print | wc -l)" = 1
rm "$persistent/openvpn-ca-key"
if "$tmp_dir/activate"; then exit 1; fi
test -s "$runtime/openvpn-ca-key"
cp "$runtime/openvpn-ca-key" "$persistent/openvpn-ca-key"
rm "$persistent/root-password-hash"
if "$tmp_dir/activate"; then exit 1; fi
test -s "$runtime/admin-password-hash"
