#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

role=roles/secrets_administration/tasks/main.yml
runtime=roles/secrets_administration/templates/bastion-decrypt-secrets.sh.j2

test "$(sed -n '1p' secrets/server.yaml)" = '$ANSIBLE_VAULT;1.1;AES256'
rg -q 'Load controller-side Bastion server Vault' "$role"
rg -q 'no_log: true' "$role"
rg -q 'diff: false' "$role"
rg -q '/var/lib/bastion/secrets' "$role" "$runtime"
rg -q "mode: '0700'" "$role"
rg -q "mode: '0600'" "$role"
rg -q 'mv -Tf "\$link_path" "\$runtime_link"' "$runtime"
rg -q 'vpn_keys=0' "$runtime"
rg -q 'openssl pkey' "$runtime"
! rg -q 'openvpn-ca-key' scripts/preflight-secrets
rg -q 'legacy_ca_key' "$runtime"
! rg -q 'Remove obsolete persistent OpenVPN CA key' "$role"
rg -q 'ssh-notify.conf' "$role" "$runtime"
rg -q 'Reapply validated VPN state after secret activation' roles/vpn/tasks/main.yml
rg -q 'bastion_secrets_changed' roles/vpn/tasks/main.yml
! rg -in '(sops|SOPS_AGE_KEY_FILE|vps_age)' "$role" "$runtime" scripts/preflight-secrets Makefile inventory/secrets-input.json.example
rg -U -q 'Remove obsolete VPS ciphertext and age identity after Vault activation[\s\S]*no_log: true\n  diff: false' "$role"
activation_line=$(rg -n 'Require refreshed runtime secrets before dependent administration' "$role" | cut -d: -f1)
cleanup_line=$(rg -n 'Remove obsolete VPS ciphertext and age identity after Vault activation' "$role" | cut -d: -f1)
test "$activation_line" -lt "$cleanup_line"
! rg -q 'vault_password_file' roles
! rg -q 'secrets/server.yaml' roles/secrets_administration/tasks/main.yml
! rg -q 'vault.txt' roles playbooks
! rg -q 'ExecStartPre=/usr/bin/rm -rf /run/secrets/bastion' roles
! git grep -n -- 'AGE''-SECRET-KEY-' -- ':!tests/secrets-static-test.sh'
