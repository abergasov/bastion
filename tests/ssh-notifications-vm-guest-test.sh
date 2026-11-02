#!/usr/bin/env bash
set -euo pipefail

for unit in ssh-notify.service ssh-notify-boot.service; do
  test -f "/etc/systemd/system/${unit}.d/test-endpoint.conf"
done
systemctl restart ssh-notify.service
systemctl is-active --quiet ssh-notify.service
test "$(stat -c '%U:%G:%a' /run/secrets/bastion/ssh-notify.conf)" = root:root:600
printf 'SSH_NOTIFICATIONS_VM_ENDPOINT_READY\n'
