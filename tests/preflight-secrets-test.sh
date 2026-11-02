#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d /tmp/bastion-vault-preflight-test.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/secrets"
printf '%s\n' synthetic-vault-password > "$tmp_dir/password"
cat > "$tmp_dir/server.yaml" <<'EOF'
admin-password-hash: "$6$synthetic$admin"
root-password-hash: "$6$synthetic$root"
ssh-notify-config: |-
  SSHLogFile = /var/log/auth.log
  ServerName = bastion
  TelegramBotToken = synthetic-token
  TelegramNotifyChat = synthetic-chat
EOF
ANSIBLE_LOCAL_TEMP="$tmp_dir/ansible" ansible-vault encrypt \
  --vault-password-file "$tmp_dir/password" --output "$tmp_dir/secrets/server.yaml" "$tmp_dir/server.yaml" >/dev/null
cat > "$tmp_dir/input.json" <<EOF
{"admin_authorized_key":"ssh-ed25519 ZmFrZQ== owner@test","vault_password_file":"$tmp_dir/password","vault_secrets_file":"secrets/server.yaml"}
EOF
BASTION_ROOT="$tmp_dir" BASTION_VAULT_PASSWORD_FILE="$tmp_dir/password" \
  "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"

cat > "$tmp_dir/vpn-server.yaml" <<'EOF'
openvpn-server-key: synthetic-server-key
openvpn-ca-key: synthetic-ca-key
wireguard-server-key: synthetic-wireguard-key
EOF
ANSIBLE_LOCAL_TEMP="$tmp_dir/ansible" ansible-vault encrypt \
  --vault-password-file "$tmp_dir/password" --output "$tmp_dir/secrets/vpn-server.yaml" "$tmp_dir/vpn-server.yaml" >/dev/null
BASTION_ROOT="$tmp_dir" BASTION_VAULT_PASSWORD_FILE="$tmp_dir/password" \
  "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"

sed -i '/openvpn-ca-key/d' "$tmp_dir/vpn-server.yaml"
rm -f "$tmp_dir/secrets/vpn-server.yaml"
ANSIBLE_LOCAL_TEMP="$tmp_dir/ansible" ansible-vault encrypt \
  --vault-password-file "$tmp_dir/password" --output "$tmp_dir/secrets/vpn-server.yaml" "$tmp_dir/vpn-server.yaml" >/dev/null
if BASTION_ROOT="$tmp_dir" BASTION_VAULT_PASSWORD_FILE="$tmp_dir/password" \
  "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

sed -i 's/TelegramNotifyChat/TelegramChat/' "$tmp_dir/server.yaml"
rm -f "$tmp_dir/secrets/server.yaml"
ANSIBLE_LOCAL_TEMP="$tmp_dir/ansible" ansible-vault encrypt \
  --vault-password-file "$tmp_dir/password" --output "$tmp_dir/secrets/server.yaml" "$tmp_dir/server.yaml" >/dev/null
if BASTION_ROOT="$tmp_dir" BASTION_VAULT_PASSWORD_FILE="$tmp_dir/password" \
  "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi
