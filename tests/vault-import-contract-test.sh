#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

test "$(sed -n '1p' secrets/server.yaml)" = '$ANSIBLE_VAULT;1.1;AES256'
rg -q 'mktemp -d /tmp/bastion-vault-import' scripts/import-legacy-vault
rg -q 'ansible-vault view' scripts/import-legacy-vault
rg -q 'ansible-vault encrypt' scripts/import-legacy-vault
rg -q 'rm -rf "\$temporary"' scripts/import-legacy-vault
rg -q 'user_password' scripts/build-bastion-server-vault.py
rg -q 'root_password' scripts/build-bastion-server-vault.py
rg -q 'tg_token' scripts/build-bastion-server-vault.py
rg -q 'tg_chat' scripts/build-bastion-server-vault.py
! rg -q 'legacy\["seed"\]' scripts/build-bastion-server-vault.py
! rg -q 'legacy\["ovpn' scripts/build-bastion-server-vault.py
! rg -q 'legacy\["wg_' scripts/build-bastion-server-vault.py
! rg -q 'vault_password.*copy\|copy.*vault_password' roles scripts/import-legacy-vault

tmp_dir=$(mktemp -d /tmp/bastion-vault-import-contract.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT
printf '%s\n' synthetic-vault-password > "$tmp_dir/password"
cat > "$tmp_dir/legacy.yaml" <<'EOF'
user_password: synthetic-user-password
root_password: synthetic-root-password
tg_token: synthetic-token
tg_chat: 12345
seed: excluded-seed
EOF
ANSIBLE_LOCAL_TEMP="$tmp_dir/ansible" ansible-vault encrypt \
  --vault-password-file "$tmp_dir/password" --output "$tmp_dir/legacy.vault" "$tmp_dir/legacy.yaml" >/dev/null
before=$(sha256sum "$tmp_dir/legacy.vault" "$tmp_dir/password" | sha256sum)
mkdir "$tmp_dir/target"
"$root_dir/scripts/import-legacy-vault" "$tmp_dir/legacy.vault" "$tmp_dir/password" "$tmp_dir/target/server.yaml"
after=$(sha256sum "$tmp_dir/legacy.vault" "$tmp_dir/password" | sha256sum)
test "$before" = "$after"
test "$(sed -n '1p' "$tmp_dir/target/server.yaml")" = '$ANSIBLE_VAULT;1.1;AES256'
ANSIBLE_LOCAL_TEMP="$tmp_dir/ansible" ansible-vault view --vault-password-file "$tmp_dir/password" "$tmp_dir/target/server.yaml" |
  /usr/bin/python3 -c 'import sys,yaml; d=yaml.safe_load(sys.stdin); assert set(d) == {"admin-password-hash", "root-password-hash", "ssh-notify-config"}; assert "excluded-seed" not in str(d)'
