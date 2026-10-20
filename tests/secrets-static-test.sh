#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

private_age_prefix="AGE""-SECRET-KEY-"
if git grep -n -- "$private_age_prefix" -- ':!tests/secrets-static-test.sh'; then
  printf '%s\n' "private age identity found in tracked files" >&2
  exit 1
fi

allowed_secret_files='secrets/server.yaml'
while IFS= read -r path; do
  [ "$path" = "$allowed_secret_files" ] || {
    printf '%s\n' "unexpected tracked secret input: $path" >&2
    exit 1
  }
done < <(git ls-files secrets)

rg -q 'age.keyFile = "/var/lib/sops-nix/age/key.txt"' modules/secrets-administration.nix
rg -q 'admin-password-hash\.neededForUsers = true' modules/secrets-administration.nix
rg -q 'root-password-hash\.neededForUsers = true' modules/secrets-administration.nix
rg -q 'openvpnServerKey =' modules/secrets-administration.nix
rg -q '"/run/secrets/openvpn-server-key"' modules/secrets-administration.nix
rg -q 'wireguardServerKey =' modules/secrets-administration.nix
rg -q '"/run/secrets/wireguard-server-key"' modules/secrets-administration.nix
rg -q 'sshNotifyConfig =' modules/secrets-administration.nix
rg -q '"/run/secrets/ssh-notify-config"' modules/secrets-administration.nix
rg -q 'adminAuthorizedKey must be an ssh-ed25519 public key' scripts/install-bastion
rg -q 'vpsAgeRecipient must be set' scripts/install-bastion
rg -q 'sopsSecretsFile must be set' scripts/install-bastion
! rg -n 'initialPassword|passwordFile|sudo' modules/secrets-administration.nix
