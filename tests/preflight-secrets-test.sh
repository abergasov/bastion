#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="/tmp/bastion-ansible-venv/bin:$PATH"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
owner="age1$(printf 'q%.0s' {1..58})"
vps="age1$(printf 'p%.0s' {1..58})"
identity="$tmp_dir/vps-age-key.txt"
printf '%s\n' 'synthetic test identity' > "$identity"
chmod 600 "$identity"
mkdir "$tmp_dir/secrets"
write_ciphertext() {
  cat > "$tmp_dir/secrets/server.yaml" <<EOF
admin-password-hash: ENC[test]
root-password-hash: ENC[test]
openvpn-server-key: ENC[test]
wireguard-server-key: ENC[test]
sops:
  age:
    - recipient: $owner
    - recipient: $vps
EOF
}
write_ciphertext
mkdir "$tmp_dir/bin"
cat > "$tmp_dir/bin/age-keygen" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -y ] && [ "$2" = "$TEST_IDENTITY" ]
printf '%s\n' "$TEST_VPS_RECIPIENT"
EOF
chmod +x "$tmp_dir/bin/age-keygen"
cat > "$tmp_dir/bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = --decrypt ] && [ "$2" = --extract ] && [ -n "${SOPS_AGE_KEY_FILE:-}" ]
if [ -n "${TEST_SOPS_CALLS:-}" ]; then
  printf '%s\n' "$3" >> "$TEST_SOPS_CALLS"
fi
case "$(<"$4")" in
  *CORRUPT*) exit 1 ;;
  *EMPTY*) exit 0 ;;
esac
printf '%s\n' synthetic-secret
EOF
chmod +x "$tmp_dir/bin/sops"

write_input() {
  cat > "$tmp_dir/input.json" <<EOF
{"owner_age_recipient":"$owner","vps_age_recipient":"$vps","admin_authorized_key":"ssh-ed25519 ZmFrZQ== owner@test","vps_age_identity_file":"$identity","sops_secrets_file":"secrets/server.yaml"}
EOF
}

write_input
calls="$tmp_dir/sops-calls"
if ! PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" TEST_SOPS_CALLS="$calls" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi
test "$(wc -l < "$calls")" -eq 4
rg -qx '\["admin-password-hash"\]' "$calls"
rg -qx '\["root-password-hash"\]' "$calls"
rg -qx '\["openvpn-server-key"\]' "$calls"
rg -qx '\["wireguard-server-key"\]' "$calls"

write_input
sed -i "s/$vps/$owner/" "$tmp_dir/input.json"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

write_input
write_ciphertext
printf '%s\n' '# EMPTY' >> "$tmp_dir/secrets/server.yaml"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

write_input
printf '%s\n' 'sops: [' > "$tmp_dir/secrets/server.yaml"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

chmod 600 "$identity"
write_input
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$owner" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

write_input
mv "$identity" "$identity.absent"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi
mv "$identity.absent" "$identity"

write_input
write_ciphertext
sed -i "/recipient: $vps/d" "$tmp_dir/secrets/server.yaml"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

write_input
write_ciphertext
sed -i "s/recipient: $owner/not-recipient: invalid/" "$tmp_dir/secrets/server.yaml"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

write_input
write_ciphertext
sed -i "/recipient: $owner/d" "$tmp_dir/secrets/server.yaml"
printf '# owner recipient: %s\n' "$owner" >> "$tmp_dir/secrets/server.yaml"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

write_input
write_ciphertext
sed -i "s/recipient: $owner/recipient: $owner-suffix/" "$tmp_dir/secrets/server.yaml"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

write_input
write_ciphertext
sed -i '/root-password-hash/d' "$tmp_dir/secrets/server.yaml"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

write_input
write_ciphertext
printf '%s\n' '# CORRUPT' >> "$tmp_dir/secrets/server.yaml"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi

write_input
chmod 644 "$identity"
if PATH="$tmp_dir/bin:$PATH" TEST_IDENTITY="$identity" TEST_VPS_RECIPIENT="$vps" BASTION_ROOT="$tmp_dir" "$root_dir/scripts/preflight-secrets" "$tmp_dir/input.json"; then
  exit 1
fi
