#!/usr/bin/env bash
set -euo pipefail

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
vault_view="$tmp_dir/vault-view.yaml"
staging="$tmp_dir/server-values.yaml"

cat > "$vault_view" <<'EOF'
admin-password-hash: synthetic-admin-hash
root-password-hash: synthetic-root-hash
openvpn-server-key: synthetic-openvpn-key
wireguard-server-key: synthetic-wireguard-key
vault-password: must-not-transfer
ssh-seed: must-not-transfer
owner-ca-key: must-not-transfer
client-key: must-not-transfer
EOF

before=$(sha256sum "$vault_view" | cut -d ' ' -f 1)
awk -F ': ' '/^(admin-password-hash|root-password-hash|openvpn-server-key|wireguard-server-key):/ { print }' "$vault_view" > "$staging"
test "$before" = "$(sha256sum "$vault_view" | cut -d ' ' -f 1)"
test "$(wc -l < "$staging")" -eq 4
! rg -n 'vault-password|ssh-seed|owner-ca-key|client-key' "$staging"
! rg -n 'must-not-transfer' "$staging"
