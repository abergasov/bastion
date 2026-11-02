#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

run() {
  echo "RECOVERY_CHECK: $*"
  "$@"
}

run ./tests/platform-static-test.sh
run ./tests/preflight-secrets-test.sh
run ./tests/secrets-static-test.sh
run ./tests/vault-import-contract-test.sh
run ./tests/vpn-static-test.sh
run env SSH_NOTIFY_SKIP_PACKAGE_TEST=1 ./tests/ssh-notifications-test.sh
run /usr/bin/python3 ./tests/device-lifecycle-test.py
run bash -n ./tests/prepare-vm-fixture.sh ./tests/recovery-vm-cross-component.sh
run rg -F 'ansible-galaxy collection install -r "$tmp/repo/collections/requirements.yml"' ./tests/recovery-vm-cross-component.sh
run rg -F 'export ANSIBLE_COLLECTIONS_PATH="$collection_path"' ./tests/recovery-vm-cross-component.sh

if test "${BASTION_RECOVERY_VM:-0}" != 1; then
  echo "RECOVERY_INTEGRATION_PARTIAL: VM suites not requested; controller Vault checks passed"
  exit 0
fi

run ./tests/prepare-vm-fixture.sh
assets=${BASTION_VM_ASSETS:-/tmp/bastion-vm-assets}
keep=${BASTION_RECOVERY_VM_KEEP:-0}
run env BASTION_VM_ASSETS="$assets" ./tests/recovery-vm-cross-component.sh
run env BASTION_SSH_NOTIFICATIONS_VM_ASSETS="$assets" BASTION_SSH_NOTIFICATIONS_VM_KEEP="$keep" ./tests/ssh-notifications-vm-test.sh
run env BASTION_VPN_VM_BASE_IMAGE="$assets/resolute-lifecycle.qcow2" \
  BASTION_VPN_VM_PRIVATE_KEY="$assets/id_ed25519" \
  BASTION_VPN_VM_ADMIN_PUBLIC_KEY="$assets/id_ed25519.pub" \
  BASTION_VPN_VM_HOST_KEYS="$assets/known_hosts-lifecycle" \
  BASTION_VPN_VM_BOOTSTRAP_BECOME_PASSWORD_FILE="$assets/bootstrap-password" \
  BASTION_VPN_VM_KEEP="$keep" ./tests/vpn-vm-test.sh
test "$assets" = /tmp/bastion-vm-assets || {
  echo 'RECOVERY_INTEGRATION_PARTIAL: device lifecycle suite requires /tmp/bastion-vm-assets' >&2
  exit 2
}
run env BASTION_VPN_VM_KEEP="$keep" ./tests/device-lifecycle-vm-test.sh
echo "RECOVERY_INTEGRATION_VM_PASS: cross-component and disposable component VM suites completed"
echo "RECOVERY_INTEGRATION_PARTIAL: no live VPS or real Telegram delivery implied"
