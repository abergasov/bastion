#!/usr/bin/env bash
# Small coordination scenario.  Detailed tunnel and lifecycle behavior remains
# in the component suites; this proves their roles coexist in one recovered VM.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
assets=${BASTION_VM_ASSETS:-/tmp/bastion-vm-assets}
base=$assets/resolute-lifecycle.qcow2
key=$assets/id_ed25519
known=$assets/known_hosts-lifecycle
password=$assets/bootstrap-password
for path in "$base" "$key" "$key.pub" "$known" "$password"; do
  test -r "$path" || { echo "recovery-vm-cross-component: missing fixture: $path" >&2; exit 2; }
done
test "$(stat -c %a "$password")" = 600 || { echo 'recovery-vm-cross-component: fixture password must be mode 0600' >&2; exit 2; }
for tool in ansible ansible-playbook ansible-vault ansible-galaxy curl openssl qemu-img qemu-system-x86_64 ssh; do
  command -v "$tool" >/dev/null || { echo "recovery-vm-cross-component: missing $tool" >&2; exit 2; }
done

tmp=$(mktemp -d /tmp/bastion-recovery-cross-component.XXXXXX)
vm=''; mock=''
cleanup() {
  status=$?
  test -z "$mock" || kill "$mock" 2>/dev/null || true
  test -z "$vm" || kill "$vm" 2>/dev/null || true
  test -z "$mock" || wait "$mock" 2>/dev/null || true
  test -z "$vm" || wait "$vm" 2>/dev/null || true
  if test "${BASTION_RECOVERY_VM_KEEP:-0}" = 1; then echo "RECOVERY_CROSS_COMPONENT_EVIDENCE=$tmp"; else rm -rf "$tmp"; fi
  exit "$status"
}
trap cleanup EXIT
umask 077
cp -a "$root" "$tmp/repo"
collection_path="$tmp/collections"
ansible-galaxy collection install -r "$tmp/repo/collections/requirements.yml" -p "$collection_path" --force >/dev/null
export ANSIBLE_COLLECTIONS_PATH="$collection_path"
install -d -m 0700 "$tmp/controller" "$tmp/release/openvpn" "$tmp/release/wireguard"
port=$((39000 + RANDOM % 1000)); mock_port=$((port + 1))

printf '%s\n' synthetic-vault-password > "$tmp/controller/vault-password"
install -m 0600 "$password" "$tmp/controller/become-password"
root_hash=$(openssl passwd -6 -stdin < "$password")
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=bastion-recovery-test-ca -keyout "$tmp/controller/ca.key" -out "$tmp/release/openvpn/ca.crt" >/dev/null 2>&1
cat > "$tmp/controller/extensions.cnf" <<'EOF'
[server]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
openssl req -newkey rsa:2048 -nodes -subj /CN=bastion-recovery-test-server -keyout "$tmp/controller/server.key" -out "$tmp/controller/server.csr" >/dev/null 2>&1
openssl x509 -req -days 2 -in "$tmp/controller/server.csr" -CA "$tmp/release/openvpn/ca.crt" -CAkey "$tmp/controller/ca.key" -CAserial "$tmp/controller/ca.srl" -CAcreateserial -extfile "$tmp/controller/extensions.cnf" -extensions server -out "$tmp/release/openvpn/server.crt" >/dev/null 2>&1
touch "$tmp/controller/index.txt"
printf '1000\n' > "$tmp/controller/crlnumber"
cat > "$tmp/controller/ca.cnf" <<EOF
[ca]
default_ca = test_ca
[test_ca]
database = $tmp/controller/index.txt
private_key = $tmp/controller/ca.key
certificate = $tmp/release/openvpn/ca.crt
default_md = sha256
default_crl_days = 1
crlnumber = $tmp/controller/crlnumber
EOF
openssl ca -config "$tmp/controller/ca.cnf" -gencrl -batch -out "$tmp/release/openvpn/crl.pem" >/dev/null 2>&1
printf '{"synthetic":true}\n' > "$tmp/release/openvpn/metadata.json"
wg_private=$(openssl rand -base64 32 | tr -d '\n')
printf '%s 10.43.0.2 fd42:2::2\n' "$(openssl rand -base64 32 | tr -d '\n')" > "$tmp/release/wireguard/peers"
printf 'bastion-vpn-state-v1\n' > "$tmp/release/READY"
(cd "$tmp/release" && sha256sum openvpn/ca.crt openvpn/server.crt openvpn/crl.pem openvpn/metadata.json wireguard/peers > manifest.sha256)
chmod 0600 "$tmp/release/READY" "$tmp/release/manifest.sha256" "$tmp/release/openvpn/ca.crt" "$tmp/release/openvpn/server.crt" "$tmp/release/openvpn/crl.pem" "$tmp/release/openvpn/metadata.json" "$tmp/release/wireguard/peers"

# Match the verifier's public-release contract before copying it into the VM.
expected_release_files=$'READY\nmanifest.sha256\nopenvpn/ca.crt\nopenvpn/crl.pem\nopenvpn/metadata.json\nopenvpn/server.crt\nwireguard/peers'
test "$(find -P "$tmp/release" -xdev -type f -printf '%P\n' | sort)" = "$expected_release_files"
! find -P "$tmp/release" -xdev \( -type l -o -perm /022 \) -print -quit | grep -q .
test -f "$tmp/controller/ca.srl"
! find -P "$tmp/release" -xdev -name '*.srl' -print -quit | grep -q .
openssl verify -purpose sslserver -CAfile "$tmp/release/openvpn/ca.crt" "$tmp/release/openvpn/server.crt" >/dev/null

cat > "$tmp/controller/server.yaml" <<EOF
admin-password-hash: $root_hash
root-password-hash: $root_hash
ssh-notify-config: |
  SSHLogFile = /var/log/auth.log
  ServerName = bastion
  TelegramBotToken = synthetic-token
  TelegramNotifyChat = synthetic-chat
EOF
ansible-vault encrypt --vault-password-file "$tmp/controller/vault-password" --output "$tmp/repo/secrets/server.yaml" "$tmp/controller/server.yaml"
cat > "$tmp/controller/vpn-server.yaml" <<EOF
openvpn-server-key: |
$(sed 's/^/  /' "$tmp/controller/server.key")
wireguard-server-key: $wg_private
EOF
ansible-vault encrypt --vault-password-file "$tmp/controller/vault-password" --output "$tmp/repo/secrets/vpn-server.yaml" "$tmp/controller/vpn-server.yaml"
rm -f "$tmp/controller/server.yaml" "$tmp/controller/vpn-server.yaml" "$tmp/controller/server.csr"

python3 "$root/tests/ssh-notifications-vm-mock.py" --bind 0.0.0.0 --port "$mock_port" --log "$tmp/messages.jsonl" &
mock=$!
for _ in $(seq 1 30); do curl -fsS "http://127.0.0.1:$mock_port/" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://127.0.0.1:$mock_port/" >/dev/null

qemu-img create -f qcow2 -F qcow2 -b "$base" "$tmp/overlay.qcow2" >/dev/null
qemu-img resize "$tmp/overlay.qcow2" 20G >/dev/null
qemu-system-x86_64 -machine accel=tcg -m 2048 -smp 1 -drive "file=$tmp/overlay.qcow2,if=virtio,format=qcow2" \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=n0 \
  -display none -serial "file:$tmp/serial.log" -monitor none >"$tmp/qemu.log" 2>&1 &
vm=$!
sed -E "s/\\[127\\.0\\.0\\.1\\]:[0-9]+/[127.0.0.1]:$port/g" "$known" > "$tmp/repo/inventory/known_hosts"
ssh_common="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp/repo/inventory/known_hosts -o StrictHostKeyChecking=yes"
ssh_args=(-F /dev/null -i "$key" -p "$port" -o BatchMode=yes -o ConnectTimeout=3 -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$tmp/repo/inventory/known_hosts" -o StrictHostKeyChecking=yes)
for _ in $(seq 1 180); do ssh "${ssh_args[@]}" admin@127.0.0.1 true >/dev/null 2>&1 && break; sleep 1; done
ssh "${ssh_args[@]}" admin@127.0.0.1 true >/dev/null

cat > "$tmp/repo/inventory/recovery-cross-component.ini" <<EOF
[bastion]
bastion ansible_host=127.0.0.1 ansible_port=$port ansible_user=admin ansible_ssh_private_key_file=$key admin_authorized_key='$(<"$key.pub")' netplan_interface=ens3 ipv4_address=10.0.2.15 ipv4_prefix=24 ipv4_gateway=10.0.2.2 ipv6_address=fec0::15 ipv6_prefix=64 ipv6_gateway=fec0::2 dns_servers='["10.0.2.3","fec0::3"]'
EOF
cat > "$tmp/repo/playbooks/recovery-cross-component.yml" <<'EOF'
---
- hosts: bastion
  remote_user: admin
  become: true
  become_method: ansible.builtin.su
  gather_facts: true
  pre_tasks:
    - ansible.builtin.file:
        path: "/etc/systemd/system/{{ item }}.d"
        state: directory
        owner: root
        group: root
        mode: '0755'
      loop: [ssh-notify.service, ssh-notify-boot.service]
    - ansible.builtin.copy:
        dest: "/etc/systemd/system/{{ item }}.d/test-endpoint.conf"
        content: "[Service]\nEnvironment=SSH_NOTIFY_TELEGRAM_API_URL={{ ssh_notifications_test_endpoint | replace('%', '%%') }}\n"
        owner: root
        group: root
        mode: '0644'
      loop: [ssh-notify.service, ssh-notify-boot.service]
    - ansible.builtin.systemd_service:
        daemon_reload: true
  roles: [platform, secrets_administration, administration, firewall, vpn, ssh_notifications]
  post_tasks:
    - ansible.builtin.copy:
        src: "{{ recovery_fixture_release }}/"
        dest: /var/lib/bastion/vpn/releases/recovery
        owner: root
        group: root
        mode: '0700'
        directory_mode: '0700'
    - ansible.builtin.file:
        src: releases/recovery
        dest: /var/lib/bastion/vpn/current
        state: link
    - ansible.builtin.command:
        argv: [/usr/local/libexec/bastion-vpn-apply-state]
      changed_when: false
EOF
ansible -i "$tmp/repo/inventory/recovery-cross-component.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp/controller/become-password" --ssh-common-args="$ssh_common" --module-name shell --args 'growpart /dev/vda 1 && resize2fs /dev/vda1'
run_playbook() {
  ANSIBLE_LOCAL_TEMP="$tmp/ansible-$1" ansible-playbook -i "$tmp/repo/inventory/recovery-cross-component.ini" "$tmp/repo/playbooks/recovery-cross-component.yml" \
    --vault-password-file "$tmp/controller/vault-password" --extra-vars vault_secrets_file=secrets/server.yaml \
    --extra-vars recovery_fixture_release="$tmp/release" --extra-vars ssh_notifications_test_endpoint="http://10.0.2.2:$mock_port/bot%s/sendMessage" \
    --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$tmp/controller/become-password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common" | tee "$tmp/$1.log"
}
run_playbook initial
rg -q 'bastion[[:space:]]*:.*failed=0' "$tmp/initial.log"
ansible -i "$tmp/repo/inventory/recovery-cross-component.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp/controller/become-password" --ssh-common-args="$ssh_common" --module-name shell --args 'systemctl is-active --quiet bastion-secrets.service ssh-notify.service bastion-vpn-apply.service openvpn-server@bastion.service; test "$(stat -c %a /run/secrets/bastion/ssh-notify.conf)" = 600'
run_playbook repeated
rg -q 'bastion[[:space:]]*:.*changed=0.*failed=0' "$tmp/repeated.log"
ssh "${ssh_args[@]}" admin@127.0.0.1 true
for _ in $(seq 1 30); do rg -q 'New server login' "$tmp/messages.jsonl" && break; sleep 1; done
rg -q 'New server login' "$tmp/messages.jsonl"
ansible -i "$tmp/repo/inventory/recovery-cross-component.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp/controller/become-password" --ssh-common-args="$ssh_common" --module-name reboot --args 'reboot_timeout=240'
ansible -i "$tmp/repo/inventory/recovery-cross-component.ini" bastion --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp/controller/become-password" --ssh-common-args="$ssh_common" --module-name shell --args 'systemctl is-active --quiet bastion-secrets.service ssh-notify.service bastion-vpn-apply.service openvpn-server@bastion.service'
for _ in $(seq 1 30); do rg -q 'ssh notify server booted' "$tmp/messages.jsonl" && break; sleep 1; done
rg -q 'ssh notify server booted' "$tmp/messages.jsonl"
echo RECOVERY_CROSS_COMPONENT_VM_PASS
