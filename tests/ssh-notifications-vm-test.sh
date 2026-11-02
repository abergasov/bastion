#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
assets=${BASTION_SSH_NOTIFICATIONS_VM_ASSETS:-/tmp/bastion-vm-assets}
base=${BASTION_SSH_NOTIFICATIONS_VM_BASE_IMAGE:-$assets/resolute-lifecycle.qcow2}
key=${BASTION_SSH_NOTIFICATIONS_VM_PRIVATE_KEY:-$assets/id_ed25519}
known=${BASTION_SSH_NOTIFICATIONS_VM_HOST_KEYS:-$assets/known_hosts-lifecycle}
password=${BASTION_SSH_NOTIFICATIONS_VM_BOOTSTRAP_PASSWORD_FILE:-$assets/bootstrap-password}
seed_iso=${BASTION_SSH_NOTIFICATIONS_VM_SEED_ISO:-}
port=${BASTION_SSH_NOTIFICATIONS_VM_PORT:-$((34000 + RANDOM % 2000))}
mock_port=$((port + 1))
ssh_wait_attempts=${BASTION_SSH_NOTIFICATIONS_VM_SSH_WAIT_ATTEMPTS:-180}

for path in "$base" "$key" "$known" "$password"; do
  test -r "$path" || { printf 'ssh-notifications-vm-test: missing readable fixture: %s\n' "$path" >&2; exit 2; }
done
test "$(stat -c %a "$password")" = 600 || { echo 'ssh-notifications-vm-test: bootstrap password must be mode 0600' >&2; exit 2; }
command -v qemu-system-x86_64 >/dev/null
command -v ansible-playbook >/dev/null
command -v ansible-vault >/dev/null
test -z "$seed_iso" || test -r "$seed_iso" || { printf 'ssh-notifications-vm-test: missing readable seed ISO: %s\n' "$seed_iso" >&2; exit 2; }

tmp=$(mktemp -d /tmp/bastion-ssh-notifications-vm.XXXXXX)
vm=''; mock=''
cleanup() {
  status=$?
  set +e
  if test "$status" -ne 0; then
    {
      echo 'ssh-notifications-vm-test: redacted ssh-notify journal follows'
      if test -f "$tmp/repo/inventory/ssh-notifications-vm.ini" && test -n "${ssh_common:-}"; then
        timeout 30 ansible -i "$tmp/repo/inventory/ssh-notifications-vm.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$password" --ssh-common-args="$ssh_common" --module-name shell --args 'journalctl -u ssh-notify.service -n 100 --no-pager || true' 2>&1
      else
        echo 'ssh-notifications-vm-test: ssh-notify journal unavailable before VM provisioning'
      fi
      echo 'ssh-notifications-vm-test: mock log follows'
      test -f "$tmp/messages.jsonl" && sed -n '1,200p' "$tmp/messages.jsonl" || true
    } | sed -E -e 's#(bot)[^/[:space:]]+(/sendMessage)#\1[REDACTED]\2#g' -e 's#(Telegram(BotToken|NotifyChat)[[:space:]]*=[[:space:]]*)[^[:space:]]+#\1[REDACTED]#g' >&2
  fi
  test -z "$mock" || kill "$mock" 2>/dev/null || true
  test -z "$vm" || kill "$vm" 2>/dev/null || true
  test -z "$mock" || wait "$mock" 2>/dev/null || true
  test -z "$vm" || wait "$vm" 2>/dev/null || true
  if test "${BASTION_SSH_NOTIFICATIONS_VM_KEEP:-0}" = 1; then echo "SSH_NOTIFICATIONS_VM_EVIDENCE=$tmp"; else rm -rf "$tmp"; fi
  return "$status"
}
trap cleanup EXIT

cp -a "$root" "$tmp/repo"
cd "$tmp/repo"
install -d -m 0700 "$tmp/controller" "$tmp/bin"
install -d -m 0700 "$tmp/repo/inventory"
vault_password="$tmp/controller/vault-password"
printf '%s\n' synthetic-vault-password > "$vault_password"
chmod 600 "$vault_password"
root_hash=$(openssl passwd -6 -stdin < "$password")
cat > "$tmp/controller/server.yaml" <<EOF
admin-password-hash: $root_hash
root-password-hash: $root_hash
ssh-notify-config: |
  SSHLogFile = /var/log/auth.log
  ServerName = bastion
  TelegramBotToken = fixture-token
  TelegramNotifyChat = fixture-chat
EOF
ANSIBLE_LOCAL_TEMP="$tmp/ansible-vault" ansible-vault encrypt --vault-password-file "$vault_password" --output "$tmp/repo/secrets/server.yaml" "$tmp/controller/server.yaml"
rm -f "$tmp/controller/server.yaml"
for name in admin-password-hash root-password-hash ssh-notify-config; do
  ANSIBLE_LOCAL_TEMP="$tmp/ansible-vault-view" ansible-vault view --vault-password-file "$vault_password" "$tmp/repo/secrets/server.yaml" | rg -q "^${name}:"
done

python3 "$root/tests/ssh-notifications-vm-mock.py" --bind 0.0.0.0 --port "$mock_port" --log "$tmp/messages.jsonl" &
mock=$!
mock_url="http://127.0.0.1:$mock_port"
mock_control() { curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"failures\":$1}" "$mock_url/control" >/dev/null; }
mock_attempts() { curl -fsS "$mock_url" | python3 -c 'import json, sys; print(json.load(sys.stdin)["attempts"])'; }
wait_for_attempts() { for _ in $(seq 1 30); do test "$(mock_attempts)" = "$1" && return; sleep 1; done; echo "ssh-notifications-vm-test: attempts did not reach $1" >&2; return 1; }
for _ in $(seq 1 30); do mock_control 0 && break; sleep 1; done
mock_control 0
qemu-img create -f qcow2 -F qcow2 -b "$base" "$tmp/overlay.qcow2" >/dev/null
qemu-img resize "$tmp/overlay.qcow2" 20G >/dev/null
qemu_args=(-machine accel=tcg -m 2048 -smp 1 -drive "file=$tmp/overlay.qcow2,if=virtio,format=qcow2")
test -z "$seed_iso" || qemu_args+=(-drive "file=$seed_iso,media=cdrom,readonly=on")
qemu-system-x86_64 "${qemu_args[@]}" -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=n0 -display none -serial "file:$tmp/serial.log" -monitor none >"$tmp/qemu.log" 2>&1 &
vm=$!
sed -E "s/\\[127\\.0\\.0\\.1\\]:[0-9]+/[127.0.0.1]:$port/g" "$known" > "$tmp/repo/inventory/known_hosts"
strict_host_key_checking=yes
test -s "$tmp/repo/inventory/known_hosts" || { echo 'ssh-notifications-vm-test: expected known_hosts is empty' >&2; exit 2; }
ssh_args=(-F /dev/null -i "$key" -p "$port" -o BatchMode=yes -o ConnectTimeout=3 -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$tmp/repo/inventory/known_hosts" -o StrictHostKeyChecking="$strict_host_key_checking")
for _ in $(seq 1 "$ssh_wait_attempts"); do ssh "${ssh_args[@]}" admin@127.0.0.1 true >/dev/null 2>&1 && break; sleep 1; done
ssh "${ssh_args[@]}" admin@127.0.0.1 true >/dev/null

cat > "$tmp/repo/playbooks/ssh-notifications-vm.yml" <<'EOF'
---
- hosts: bastion
  remote_user: admin
  become: true
  become_method: ansible.builtin.su
  gather_facts: true
  pre_tasks:
    - name: Create test-only notification endpoint drop-ins
      ansible.builtin.file:
        path: "/etc/systemd/system/{{ item }}.d"
        state: directory
        owner: root
        group: root
        mode: '0755'
      loop:
        - ssh-notify.service
        - ssh-notify-boot.service

    - name: Route notifications to the local test endpoint
      ansible.builtin.copy:
        dest: "/etc/systemd/system/{{ item }}.d/test-endpoint.conf"
        content: |
          [Service]
          Environment=SSH_NOTIFY_TELEGRAM_API_URL={{ ssh_notifications_test_endpoint | replace('%', '%%') }}
        owner: root
        group: root
        mode: '0644'
      loop:
        - ssh-notify.service
        - ssh-notify-boot.service

    - name: Reload systemd after the test endpoint setup
      ansible.builtin.systemd_service:
        daemon_reload: true
  roles: [platform, secrets_administration, administration, ssh_notifications]
EOF
cat > "$tmp/repo/inventory/ssh-notifications-vm.ini" <<EOF
[bastion]
bastion ansible_host=127.0.0.1 ansible_port=$port ansible_user=admin ansible_ssh_private_key_file=$key admin_authorized_key='$(<"$key.pub")' netplan_interface=ens3 ipv4_address=10.0.2.15 ipv4_prefix=24 ipv4_gateway=10.0.2.2 ipv6_address=fec0::15 ipv6_prefix=64 ipv6_gateway=fec0::2 dns_servers='["10.0.2.3","fec0::3"]'
EOF
ssh_common="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes"
ansible -i "$tmp/repo/inventory/ssh-notifications-vm.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$password" --ssh-common-args="$ssh_common" --module-name shell --args 'output=$(growpart /dev/vda 1 2>&1) || { status=$?; case "$status:$output" in "1:NOCHANGE: partition 1 is size "*". it cannot be grown") ;; *) printf "%s\\n" "$output" >&2; exit "$status";; esac; }; printf "%s\\n" "$output"; resize2fs /dev/vda1'
ANSIBLE_LOCAL_TEMP="$tmp/ansible" ansible-playbook -i "$tmp/repo/inventory/ssh-notifications-vm.ini" "$tmp/repo/playbooks/ssh-notifications-vm.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars ssh_notifications_test_endpoint="http://10.0.2.2:$mock_port/bot%s/sendMessage" --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$password" --ssh-common-args="$ssh_common" | tee "$tmp/play.log"
rg -q 'bastion[[:space:]]*:.*failed=0' "$tmp/play.log"
notifier_started() {
  ansible -i "$tmp/repo/inventory/ssh-notifications-vm.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$password" --ssh-common-args="$ssh_common" --module-name command --args 'systemctl show --property=ActiveEnterTimestampMonotonic --value ssh-notify.service' | sed -n '/^[0-9][0-9]*$/p' | tail -1
}
notifier_before_refresh=$(notifier_started)
ansible -i "$tmp/repo/inventory/ssh-notifications-vm.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$password" --ssh-common-args="$ssh_common" --module-name command --args 'systemctl restart bastion-secrets.service'
notifier_after_refresh=$(notifier_started)
test "$notifier_after_refresh" != "$notifier_before_refresh"
ANSIBLE_LOCAL_TEMP="$tmp/ansible-reapply" ansible-playbook -i "$tmp/repo/inventory/ssh-notifications-vm.ini" "$tmp/repo/playbooks/ssh-notifications-vm.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars ssh_notifications_test_endpoint="http://10.0.2.2:$mock_port/bot%s/sendMessage" --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$password" --ssh-common-args="$ssh_common" | tee "$tmp/reapply.log"
rg -q 'bastion[[:space:]]*:.*changed=0.*failed=0' "$tmp/reapply.log"
mock_message_count() {
  local count
  count=$(rg -c -- "$1" "$tmp/messages.jsonl" 2>/dev/null || true)
  printf '%s\n' "${count:-0}"
}
boot_messages_before=$(mock_message_count 'ssh notify server booted')
ansible -i "$tmp/repo/inventory/ssh-notifications-vm.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$password" --ssh-common-args="$ssh_common" --module-name script --args "$root/tests/ssh-notifications-vm-guest-test.sh"
sleep 2
test "$(mock_message_count 'ssh notify server booted')" = "$boot_messages_before"

wait_for() { for _ in $(seq 1 30); do rg -q "$1" "$tmp/messages.jsonl" 2>/dev/null && return; sleep 1; done; echo "ssh-notifications-vm-test: missing notification: $1" >&2; return 1; }
login_messages() { mock_message_count 'New server login'; }
wait_for_login_count() { for _ in $(seq 1 30); do test "$(login_messages)" -ge "$1" && return; sleep 1; done; echo 'ssh-notifications-vm-test: login notification count did not increase' >&2; return 1; }
fresh_login() {
  login_messages_before=$(login_messages)
  ssh "${ssh_args[@]}" admin@127.0.0.1 true
  wait_for_login_count "$((login_messages_before + 1))"
}
mock_control 0
login_messages_before=$(login_messages)
ssh "${ssh_args[@]}" admin@127.0.0.1 true
wait_for_login_count "$((login_messages_before + 1))"
wait_for_attempts 1
ansible -i "$tmp/repo/inventory/ssh-notifications-vm.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$password" --ssh-common-args="$ssh_common" --module-name command --args 'logrotate -f /etc/logrotate.conf'
login_messages_before=$(login_messages)
ssh "${ssh_args[@]}" admin@127.0.0.1 true
wait_for_login_count "$((login_messages_before + 1))"
wait_for_attempts 2
mock_control 2
fresh_login
wait_for_attempts 3
mock_control 6
fresh_login
wait_for_attempts 6
mock_control 0
fresh_login
wait_for_attempts 1
mock_control 0
boot_messages_before=$(mock_message_count 'ssh notify server booted')
ansible -i "$tmp/repo/inventory/ssh-notifications-vm.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$password" --ssh-common-args="$ssh_common" --module-name reboot --args 'reboot_timeout=240'
boot_messages_expected=$((boot_messages_before + 1))
for _ in $(seq 1 30); do test "$(mock_message_count 'ssh notify server booted')" = "$boot_messages_expected" && break; sleep 1; done
test "$(mock_message_count 'ssh notify server booted')" = "$boot_messages_expected"
echo SSH_NOTIFICATIONS_VM_PASS
