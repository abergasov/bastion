#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

base_image=${BASTION_VPN_VM_BASE_IMAGE:-/tmp/bastion-full-verify-j90q474f/disk-fixed.qcow2}
private_key=${BASTION_VPN_VM_PRIVATE_KEY:-/tmp/bastion-vm-root-seed/id_ed25519}
admin_public_key=${BASTION_VPN_VM_ADMIN_PUBLIC_KEY:-$private_key.pub}
host_keys=${BASTION_VPN_VM_HOST_KEYS:-/tmp/bastion-full-verify-j90q474f/known_hosts}
bootstrap_become_password=${BASTION_VPN_VM_BOOTSTRAP_BECOME_PASSWORD_FILE:?set a mode-0600 file containing the fixture existing synthetic root password}
port=${BASTION_VPN_VM_PORT:-$((20000 + RANDOM % 20000))}
peer_port=$((port + 3))
peer_socket_port=$((port + 4))
for path in "$base_image" "$private_key" "$admin_public_key" "$host_keys" "$bootstrap_become_password"; do
  test -r "$path" || { printf 'vpn-vm-test: missing readable fixture: %s\n' "$path" >&2; exit 1; }
done
command -v ansible-vault >/dev/null
test "$(stat -c '%a' "$bootstrap_become_password")" = 600 || { echo 'vpn-vm-test: bootstrap password file must have mode 0600' >&2; exit 1; }
[[ "$port" =~ ^[0-9]{2,5}$ && "$peer_socket_port" -le 65535 ]] || { echo 'vpn-vm-test: invalid loopback port' >&2; exit 1; }

tmp_root=$(mktemp -d /tmp/bastion-vpn-vm.XXXXXX)
umask 077
vm_pid=''
peer_pid=''
keep_fixture=${BASTION_VPN_VM_KEEP:-0}
crl_only=0
seeded_cleanup_ready=0
seeded_server_helper=''
cleanup() {
  if test "$seeded_cleanup_ready" = 1; then
    ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$seeded_server_helper cleanup" >/dev/null 2>&1 || true
    ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --seeded-isolation-cleanup' >/dev/null 2>&1 || true
  fi
  test -z "$peer_pid" || kill "$peer_pid" 2>/dev/null || true
  test -z "$vm_pid" || kill "$vm_pid" 2>/dev/null || true
  test -z "$peer_pid" || wait "$peer_pid" 2>/dev/null || true
  test -z "$vm_pid" || wait "$vm_pid" 2>/dev/null || true
  if test "$keep_fixture" = 1; then printf 'VPN VM evidence directory: %s\n' "$tmp_root"; else rm -rf "$tmp_root"; fi
}
trap cleanup EXIT
export ANSIBLE_LOCAL_TEMP="$tmp_root/local"
export ANSIBLE_HOME="$tmp_root/home"
install -d -m 0700 "$ANSIBLE_LOCAL_TEMP" "$ANSIBLE_HOME" "$tmp_root/playbooks" "$tmp_root/secrets" "$tmp_root/peer" "$tmp_root/public-states"
command -v ansible-galaxy >/dev/null || { echo 'vpn-vm-test: ansible-galaxy is required to install pinned collections' >&2; exit 1; }
collection_path="$tmp_root/collections"
if test -n "${BASTION_VPN_VM_COLLECTIONS_PATH:-}" && test -d "${BASTION_VPN_VM_COLLECTIONS_PATH}/ansible_collections/community/general"; then
  collection_path=$BASTION_VPN_VM_COLLECTIONS_PATH
else
  if ! ansible-galaxy collection install -r collections/requirements.yml -p "$collection_path" --force >/dev/null; then
    echo 'vpn-vm-test: failed to install pinned Ansible collections into isolated path' >&2
    exit 1
  fi
fi
export ANSIBLE_COLLECTIONS_PATH="$collection_path"
test -d "$collection_path/ansible_collections/community/general" || {
  echo 'vpn-vm-test: installed community.general collection is missing' >&2
  exit 1
}

make_release() {
  local name=$1 crl=$2
  local crl_number crl_sequence=4096
  local release="$tmp_root/public-states/$name"
  if crl_number=$(openssl crl -in "$crl" -noout -crlnumber 2>/dev/null | sed 's/.*=0x//'); then
    [[ "$crl_number" =~ ^[0-9A-Fa-f]+$ ]] && crl_sequence=$((16#$crl_number))
  fi
  install -d -m 0700 "$release/openvpn" "$release/wireguard"
  install -m 0644 "$tmp_root/peer/ca.crt" "$release/openvpn/ca.crt"
  install -m 0644 "$tmp_root/peer/server.crt" "$release/openvpn/server.crt"
  install -m 0644 "$crl" "$release/openvpn/crl.pem"
  install -m 0644 "$tmp_root/peer/index.txt" "$release/openvpn/index.txt"
  printf '%s\n' "{\"version\":2,\"membership_revision\":1,\"crl_sequence\":$crl_sequence,\"openvpn_clients\":[],\"revocations\":[]}" > "$release/openvpn/metadata.json"
  printf '%s 10.43.0.2 fd42:2::2\n' "$(openssl rand -base64 32 | tr -d '\n')" > "$release/wireguard/peers"
  printf 'bastion-vpn-state-v1\n' > "$release/READY"
  (cd "$release" && sha256sum openvpn/ca.crt openvpn/server.crt openvpn/crl.pem openvpn/index.txt openvpn/metadata.json wireguard/peers > manifest.sha256)
}

# This directory is controller/test-peer only. No CA or client private key is
# copied into the VPS public-state fixture.
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=bastion-vpn-test-ca -keyout "$tmp_root/peer/ca.key" -out "$tmp_root/peer/ca.crt" >/dev/null 2>&1
cat > "$tmp_root/peer/extensions.cnf" <<'EOF'
[server]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
[client]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF
openssl req -newkey rsa:2048 -nodes -subj /CN=bastion-vpn-test-server -keyout "$tmp_root/peer/server.key" -out "$tmp_root/peer/server.csr" >/dev/null 2>&1
openssl x509 -req -days 2 -in "$tmp_root/peer/server.csr" -CA "$tmp_root/peer/ca.crt" -CAkey "$tmp_root/peer/ca.key" -CAcreateserial -extfile "$tmp_root/peer/extensions.cnf" -extensions server -out "$tmp_root/peer/server.crt" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj /CN=bastion-vpn-test-client -keyout "$tmp_root/peer/client.key" -out "$tmp_root/peer/client.csr" >/dev/null 2>&1
openssl x509 -req -days 2 -in "$tmp_root/peer/client.csr" -CA "$tmp_root/peer/ca.crt" -CAkey "$tmp_root/peer/ca.key" -CAcreateserial -extfile "$tmp_root/peer/extensions.cnf" -extensions client -out "$tmp_root/peer/client.crt" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj /CN=bastion-vpn-test-client-b -keyout "$tmp_root/peer/client-b.key" -out "$tmp_root/peer/client-b.csr" >/dev/null 2>&1
openssl x509 -req -days 2 -in "$tmp_root/peer/client-b.csr" -CA "$tmp_root/peer/ca.crt" -CAkey "$tmp_root/peer/ca.key" -CAcreateserial -extfile "$tmp_root/peer/extensions.cnf" -extensions client -out "$tmp_root/peer/client-b.crt" >/dev/null 2>&1
touch "$tmp_root/peer/index.txt"
printf '1000\n' > "$tmp_root/peer/crlnumber"
cat > "$tmp_root/peer/ca.cnf" <<EOF
[ ca ]
default_ca = ca
[ ca ]
database = $tmp_root/peer/index.txt
private_key = $tmp_root/peer/ca.key
certificate = $tmp_root/peer/ca.crt
default_md = sha256
default_crl_days = 30
crlnumber = $tmp_root/peer/crlnumber
EOF
openssl ca -config "$tmp_root/peer/ca.cnf" -gencrl -out "$tmp_root/peer/crl.pem" -batch >/dev/null 2>&1
# `openssl x509` issued the fixture clients directly; register A locally so
# `openssl ca -revoke` can generate the lifecycle CRL later.  This controller
# file never reaches the VPS.
client_a_expiry=$(date -u -d "$(openssl x509 -in "$tmp_root/peer/client.crt" -noout -enddate | cut -d= -f2)" +%y%m%d%H%M%SZ)
client_a_serial=$(openssl x509 -in "$tmp_root/peer/client.crt" -noout -serial | cut -d= -f2)
printf 'V\t%s\t\t%s\tunknown\t/CN=bastion-vpn-test-client\n' "$client_a_expiry" "$client_a_serial" > "$tmp_root/peer/index.txt"
openssl ca -config "$tmp_root/peer/ca.cnf" -gencrl -crl_lastupdate 20200101000000Z -crl_nextupdate 20200102000000Z -out "$tmp_root/peer/expired.pem" -batch >/dev/null 2>&1
openssl ca -config "$tmp_root/peer/ca.cnf" -gencrl -crldays 1 -out "$tmp_root/peer/due.pem" -batch >/dev/null 2>&1
printf 'not a CRL\n' > "$tmp_root/peer/invalid.pem"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=forged-crl-ca -keyout "$tmp_root/peer/forged-ca.key" -out "$tmp_root/peer/forged-ca.crt" >/dev/null 2>&1
touch "$tmp_root/peer/forged-index.txt"
printf '2000\n' > "$tmp_root/peer/forged-crlnumber"
sed "s#$tmp_root/peer/ca.key#$tmp_root/peer/forged-ca.key#; s#$tmp_root/peer/ca.crt#$tmp_root/peer/forged-ca.crt#; s#$tmp_root/peer/index.txt#$tmp_root/peer/forged-index.txt#; s#$tmp_root/peer/crlnumber#$tmp_root/peer/forged-crlnumber#" "$tmp_root/peer/ca.cnf" > "$tmp_root/peer/forged-ca.cnf"
openssl ca -config "$tmp_root/peer/forged-ca.cnf" -gencrl -out "$tmp_root/peer/forged.pem" -batch >/dev/null 2>&1
make_release valid "$tmp_root/peer/crl.pem"
make_release due "$tmp_root/peer/due.pem"
make_release forged "$tmp_root/peer/forged.pem"
make_release expired "$tmp_root/peer/expired.pem"
make_release invalid "$tmp_root/peer/invalid.pem"
make_release missing "$tmp_root/peer/crl.pem"
make_release unreadable "$tmp_root/peer/crl.pem"

qemu-img create -f qcow2 -F qcow2 -b "$base_image" "$tmp_root/overlay.qcow2" >/dev/null
qemu-img resize "$tmp_root/overlay.qcow2" 20G >/dev/null
qemu-system-x86_64 -machine accel=tcg -m 2048 -smp 1 -drive "file=$tmp_root/overlay.qcow2,if=virtio,format=qcow2" -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=n0 -netdev "socket,id=peer0,listen=127.0.0.1:$peer_socket_port" -device virtio-net-pci,netdev=peer0,mac=52:54:00:12:34:57 -display none -serial "file:$tmp_root/serial.log" -monitor none >"$tmp_root/qemu.log" 2>&1 &
vm_pid=$!
sleep 1
if ! kill -0 "$vm_pid" 2>/dev/null; then cat "$tmp_root/qemu.log" >&2; exit 1; fi

if test "$crl_only" != 1; then
  qemu-img create -f qcow2 -F qcow2 -b "$base_image" "$tmp_root/peer.qcow2" >/dev/null
  qemu-system-x86_64 -machine accel=tcg -m 1024 -smp 1 -drive "file=$tmp_root/peer.qcow2,if=virtio,format=qcow2" -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$peer_port-:22" -device virtio-net-pci,netdev=n0 -netdev "socket,id=peer0,connect=127.0.0.1:$peer_socket_port" -device virtio-net-pci,netdev=peer0,mac=52:54:00:12:34:58 -display none -serial "file:$tmp_root/peer-serial.log" -monitor none >"$tmp_root/peer-qemu.log" 2>&1 &
  peer_pid=$!
  sleep 1
  if ! kill -0 "$peer_pid" 2>/dev/null; then cat "$tmp_root/peer-qemu.log" >&2; exit 1; fi
fi

sed -E "s/\\[127\.0\.0\.1\\]:[0-9]+/[127.0.0.1]:$port/g" "$host_keys" > "$tmp_root/known_hosts"
if test "$crl_only" != 1; then
  sed -E "s/\\[127\.0\.0\.1\\]:[0-9]+/[127.0.0.1]:$peer_port/g" "$host_keys" >> "$tmp_root/known_hosts"
fi
ssh_args=(-F /dev/null -i "$private_key" -p "$port" -o BatchMode=yes -o ConnectTimeout=3 -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$tmp_root/known_hosts" -o StrictHostKeyChecking=yes)
for _ in $(seq 1 90); do ssh "${ssh_args[@]}" admin@127.0.0.1 true >/dev/null 2>&1 && break; sleep 2; done
ssh "${ssh_args[@]}" admin@127.0.0.1 true >/dev/null
if test "$crl_only" != 1; then
  peer_ssh_args=(-F /dev/null -i "$private_key" -p "$peer_port" -o BatchMode=yes -o ConnectTimeout=3 -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$tmp_root/known_hosts" -o StrictHostKeyChecking=yes)
  for _ in $(seq 1 90); do ssh "${peer_ssh_args[@]}" admin@127.0.0.1 true >/dev/null 2>&1 && break; sleep 2; done
  ssh "${peer_ssh_args[@]}" admin@127.0.0.1 true >/dev/null
  cat > "$tmp_root/peer-inventory.yml" <<EOF
all:
  hosts:
    peer:
      ansible_host: 127.0.0.1
      ansible_port: $peer_port
      ansible_user: admin
      ansible_ssh_private_key_file: $private_key
EOF
  ansible -i "$tmp_root/peer-inventory.yml" all -m ansible.builtin.apt -a 'name=openvpn,wireguard-tools,nftables state=present update_cache=true' --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp_root/known_hosts -o StrictHostKeyChecking=yes"
  ssh "${peer_ssh_args[@]}" admin@127.0.0.1 'wg genkey > /tmp/wg-client.key && chmod 600 /tmp/wg-client.key && wg pubkey < /tmp/wg-client.key > /tmp/wg-client.pub'
  wg_client_public=$(ssh "${peer_ssh_args[@]}" admin@127.0.0.1 'cat /tmp/wg-client.pub')
  ssh "${peer_ssh_args[@]}" admin@127.0.0.1 'wg genkey > /tmp/wg-client-b.key && chmod 600 /tmp/wg-client-b.key && wg pubkey < /tmp/wg-client-b.key > /tmp/wg-client-b.pub'
  wg_client_b_public=$(ssh "${peer_ssh_args[@]}" admin@127.0.0.1 'cat /tmp/wg-client-b.pub')
  printf '%s 10.43.0.2 fd42:2::2\n%s 10.43.0.3 fd42:2::3\n' "$wg_client_public" "$wg_client_b_public" > "$tmp_root/public-states/valid/wireguard/peers"
  (cd "$tmp_root/public-states/valid" && sha256sum openvpn/ca.crt openvpn/server.crt openvpn/crl.pem openvpn/index.txt openvpn/metadata.json wireguard/peers > manifest.sha256)
fi

install -m 0600 "$bootstrap_become_password" "$tmp_root/become-password"
vault_password="$tmp_root/vault-password"
printf '%s\n' synthetic-vault-password > "$vault_password"
chmod 600 "$vault_password"
openssl passwd -6 -salt bastionvpnfixture -stdin < "$tmp_root/become-password" > "$tmp_root/password-hash"
cat > "$tmp_root/secrets/plain.yaml" <<EOF
admin-password-hash: $(cat "$tmp_root/password-hash")
root-password-hash: $(cat "$tmp_root/password-hash")
ssh-notify-config: |
  SSHLogFile = /var/log/auth.log
  ServerName = bastion
  TelegramBotToken = synthetic-token
  TelegramNotifyChat = synthetic-chat
EOF
ANSIBLE_LOCAL_TEMP="$tmp_root/ansible-vault" ansible-vault encrypt --vault-password-file "$vault_password" --output "$tmp_root/secrets/server.yaml" "$tmp_root/secrets/plain.yaml"
cat > "$tmp_root/secrets/vpn-server.yaml" <<EOF
openvpn-server-key: |
$(sed 's/^/  /' "$tmp_root/peer/server.key")
wireguard-server-key: $(openssl rand -base64 32 | tr -d '\n')
EOF
ANSIBLE_LOCAL_TEMP="$tmp_root/ansible-vault-vpn" ansible-vault encrypt --vault-password-file "$vault_password" --output "$tmp_root/secrets/vpn-server.vault.yaml" "$tmp_root/secrets/vpn-server.yaml"
mv "$tmp_root/secrets/vpn-server.vault.yaml" "$tmp_root/secrets/vpn-server.yaml"
rm -f "$tmp_root/secrets/plain.yaml" "$tmp_root/password-hash"

cat > "$tmp_root/playbooks/vpn.yml" <<'EOF'
---
- hosts: bastion_admin
  remote_user: admin
  become: true
  become_method: ansible.builtin.su
  gather_facts: true
  roles: [secrets_administration, administration, firewall, vpn]
  post_tasks:
    - ansible.builtin.copy:
        src: "{{ vpn_fixture_states }}/"
        dest: /tmp/bastion-vpn-fixture-states
        owner: root
        group: root
        mode: '0700'
EOF
admin_public_key_value=$(<"$admin_public_key")
cat > "$tmp_root/inventory.yml" <<EOF
all:
  children:
    bastion_admin:
      hosts:
        bastion:
          ansible_host: 127.0.0.1
          ansible_port: $port
          ansible_user: admin
          ansible_ssh_private_key_file: $private_key
          admin_authorized_key: '$admin_public_key_value'
          netplan_interface: ens4
          bastion_openvpn_verb: 3
EOF
ansible_inventory=(ansible-inventory -i "$tmp_root/inventory.yml" --list)
cat > "$tmp_root/server-net.sh" <<'SERVER_NET'
set -eu
iface=$(ip -o link show | awk -F': ' '$2 !~ /lo|ens3/ {print $2; exit}')
cat > /etc/netplan/99-bastion-vm-transport.yaml <<NETPLAN
network:
  version: 2
  ethernets:
    bastion-vm-transport:
      match:
        name: "$iface"
      dhcp4: false
      dhcp6: false
      optional: true
      addresses:
        - 192.0.2.1/24
        - 2001:db8:100::1/64
NETPLAN
chmod 600 /etc/netplan/99-bastion-vm-transport.yaml
netplan generate
ip addr replace 192.0.2.1/24 dev "$iface"
ip -6 addr replace 2001:db8:100::1/64 dev "$iface"
ip link set "$iface" up
ip -6 neigh replace 2001:db8:100::2 lladdr 52:54:00:12:34:58 nud permanent dev "$iface"
SERVER_NET
cat > "$tmp_root/peer-net.sh" <<'PEER_NET'
set -eu
iface=$(ip -o link show | awk -F': ' '$2 !~ /lo|ens3/ {print $2; exit}')
cat > /etc/netplan/99-bastion-vm-transport.yaml <<NETPLAN
network:
  version: 2
  ethernets:
    bastion-vm-transport:
      match:
        name: "$iface"
      dhcp4: false
      dhcp6: false
      optional: true
      addresses:
        - 192.0.2.2/24
        - 2001:db8:100::2/64
NETPLAN
chmod 600 /etc/netplan/99-bastion-vm-transport.yaml
netplan generate
ip addr replace 192.0.2.2/24 dev "$iface"
ip -6 addr replace 2001:db8:100::2/64 dev "$iface"
ip link set "$iface" up
ip -6 neigh replace 2001:db8:100::1 lladdr 52:54:00:12:34:57 nud permanent dev "$iface"
PEER_NET
ssh_common="-F /dev/null -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$tmp_root/known_hosts -o StrictHostKeyChecking=yes"
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name shell --args 'growpart /dev/vda 1 && resize2fs /dev/vda1 && test "$(df --output=avail -k / | tail -n1)" -gt 10485760'
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/server-net.sh"
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/peer-net.sh"
"${ansible_inventory[@]}" | rg -q '"bastion"' || { echo 'vpn-vm-test: inventory has no bastion host' >&2; exit 1; }
set +e
ansible-playbook -i "$tmp_root/inventory.yml" "$tmp_root/playbooks/vpn.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars vpn_fixture_states="$tmp_root/public-states" --extra-vars bastion_apply_final_ssh_policy=false --extra-vars netplan_interface='bad/interface' --become-password-file "$tmp_root/become-password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common" >"$tmp_root/validation-failure.log" 2>&1
validation_rc=$?
set -e
test "$validation_rc" -ne 0 || { echo 'vpn-vm-test: invalid-interface apply unexpectedly succeeded' >&2; exit 1; }
ansible-playbook -i "$tmp_root/inventory.yml" "$tmp_root/playbooks/vpn.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars vpn_fixture_states="$tmp_root/public-states" --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$tmp_root/become-password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common" | tee "$tmp_root/play.log"
rg -q 'bastion[[:space:]]*:.*failed=0' "$tmp_root/play.log" || { echo 'vpn-vm-test: playbook did not report successful bastion recap' >&2; exit 1; }
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-guest-test.sh /tmp/bastion-vpn-fixture-states' | tee "$tmp_root/guest.log"
rg -q 'VPN_VM_FIXTURE_PASS' "$tmp_root/guest.log" || { echo 'vpn-vm-test: guest fixture marker missing' >&2; exit 1; }
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-guest-test.sh --firewall-runtime-check' | tee "$tmp_root/firewall-runtime.log"
rg -q 'VPN_VM_FIREWALL_RUNTIME_PASS' "$tmp_root/firewall-runtime.log" || { echo 'vpn-vm-test: firewall runtime marker missing' >&2; exit 1; }
cat > "$tmp_root/prepare-fail2ban-ssh-probe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
install -d -m 0700 -o admin -g admin /home/admin/.ssh
cat /tmp/ban-probe-key.pub >> /home/admin/.ssh/authorized_keys
chown admin:admin /home/admin/.ssh/authorized_keys
chmod 0600 /home/admin/.ssh/authorized_keys
EOF
ssh-keygen -q -t ed25519 -N '' -f "$tmp_root/ban-probe-key"
server_scp_args=(-F /dev/null -i "$private_key" -P "$port" -o BatchMode=yes -o ConnectTimeout=3 -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$tmp_root/known_hosts" -o StrictHostKeyChecking=yes)
peer_scp_args=(-F /dev/null -i "$private_key" -P "$peer_port" -o BatchMode=yes -o ConnectTimeout=3 -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$tmp_root/known_hosts" -o StrictHostKeyChecking=yes)
scp "${server_scp_args[@]}" "$tmp_root/ban-probe-key.pub" admin@127.0.0.1:/tmp/ban-probe-key.pub
scp "${peer_scp_args[@]}" "$tmp_root/ban-probe-key" admin@127.0.0.1:/tmp/ban-probe-key
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/prepare-fail2ban-ssh-probe.sh"
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --ssh-ban-probe available' | tee "$tmp_root/fail2ban-ssh-baseline.log"
rg -q 'VPN_VM_FAIL2BAN_SSH_BASELINE' "$tmp_root/fail2ban-ssh-baseline.log" || { echo 'vpn-vm-test: fail2ban SSH baseline marker missing' >&2; exit 1; }
cat > "$tmp_root/ban-fail2ban-probe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fail2ban-client set sshd banip 192.0.2.2 >/dev/null
fail2ban-client set sshd banip 2001:db8:100::2 >/dev/null
echo VPN_VM_FAIL2BAN_BANNED
EOF
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/ban-fail2ban-probe.sh" | tee "$tmp_root/fail2ban-ban.log"
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --ssh-ban-probe banned' | tee "$tmp_root/fail2ban-ssh-denied.log"
rg -q 'VPN_VM_FAIL2BAN_SSH_DENIED' "$tmp_root/fail2ban-ssh-denied.log" || { echo 'vpn-vm-test: fail2ban SSH denial marker missing' >&2; exit 1; }
cat > "$tmp_root/unban-fail2ban-probe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fail2ban-client set sshd unbanip 192.0.2.2 >/dev/null
fail2ban-client set sshd unbanip 2001:db8:100::2 >/dev/null
EOF
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/unban-fail2ban-probe.sh"
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --ssh-ban-probe unbanned' | tee "$tmp_root/fail2ban-ssh-restored.log"
rg -q 'VPN_VM_FAIL2BAN_SSH_RESTORED' "$tmp_root/fail2ban-ssh-restored.log" || { echo 'vpn-vm-test: fail2ban SSH restore marker missing' >&2; exit 1; }
set +e
ansible-playbook -i "$tmp_root/inventory.yml" "$tmp_root/playbooks/vpn.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars vpn_fixture_states="$tmp_root/public-states" --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$tmp_root/become-password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common" >"$tmp_root/missing-current-reapply.log" 2>&1
reapply_rc=$?
set -e
test "$reapply_rc" -ne 0 || { echo 'vpn-vm-test: missing-current reapply unexpectedly succeeded' >&2; exit 1; }
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-guest-test.sh /tmp/bastion-vpn-fixture-states assert-stopped' | tee "$tmp_root/missing-current.log"
rg -q 'VPN_VM_MISSING_CURRENT_STOPPED' "$tmp_root/missing-current.log" || { echo 'vpn-vm-test: missing-current stop marker missing' >&2; exit 1; }
cat > "$tmp_root/restore-current.sh" <<'EOF'
set -eu
ln -sfn releases/valid /var/lib/bastion/vpn/current.next
mv -Tf /var/lib/bastion/vpn/current.next /var/lib/bastion/vpn/current
/usr/local/libexec/bastion-vpn-apply-state
systemctl is-active --quiet bastion-vpn-apply.service openvpn-server@bastion.service
EOF
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/restore-current.sh"
cat > "$tmp_root/openvpn-active-enter.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'OPENVPN_ACTIVE_ENTER=%s\n' "$(systemctl show --property=ActiveEnterTimestampMonotonic --value openvpn-server@bastion.service)"
EOF
openvpn_active_enter() {
  local timestamp
  timestamp=$(ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/openvpn-active-enter.sh" | sed -n 's/.*OPENVPN_ACTIVE_ENTER=\([0-9][0-9]*\).*/\1/p' | tail -n1)
  [[ "$timestamp" =~ ^[0-9]+$ ]] || { echo 'vpn-vm-test: cannot read OpenVPN active timestamp' >&2; return 1; }
  printf '%s\n' "$timestamp"
}
openvpn_started_before=$(openvpn_active_enter)
sed -i 's/bastion_openvpn_verb: 3/bastion_openvpn_verb: 4/' "$tmp_root/inventory.yml"
ansible-playbook -i "$tmp_root/inventory.yml" "$tmp_root/playbooks/vpn.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars vpn_fixture_states="$tmp_root/public-states" --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$tmp_root/become-password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common" | tee "$tmp_root/openvpn-config-reapply.log"
rg -q 'bastion[[:space:]]*:.*changed=[1-9].*failed=0' "$tmp_root/openvpn-config-reapply.log" || { echo 'vpn-vm-test: changed OpenVPN config did not apply' >&2; exit 1; }
openvpn_started_after_config=$(openvpn_active_enter)
test "$openvpn_started_after_config" != "$openvpn_started_before" || { echo 'vpn-vm-test: changed OpenVPN config did not restart OpenVPN' >&2; exit 1; }
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name command --args 'grep -qx "verb 4" /etc/openvpn/server/bastion.conf'
# Client private material is copied only after the server listener exists, and
# only to the disposable peer VM. scp uses -P (not ssh's -p).
cat > "$tmp_root/server-wg-public.sh" <<'EOF'
set -eu
wg show wg-bastion public-key > /tmp/bastion-vpn-server-wg.pub
chmod 0644 /tmp/bastion-vpn-server-wg.pub
EOF
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/server-wg-public.sh"
scp "${server_scp_args[@]}" admin@127.0.0.1:/tmp/bastion-vpn-server-wg.pub "$tmp_root/peer/server-wg.pub"
scp "${peer_scp_args[@]}" "$tmp_root/peer/ca.crt" "$tmp_root/peer/client.crt" "$tmp_root/peer/client.key" "$tmp_root/peer/client-b.crt" "$tmp_root/peer/client-b.key" "$tmp_root/peer/server-wg.pub" admin@127.0.0.1:/tmp/
cat > "$tmp_root/peer/ovpn-a.ovpn" <<'EOF'
client
dev ovpn-a
dev-type tun
proto tcp-client
remote 192.0.2.1 443
nobind
ca /tmp/ca.crt
cert /tmp/client.crt
key /tmp/client.key
remote-cert-tls server
data-ciphers AES-256-GCM:AES-128-GCM
auth SHA256
allow-compression no
verb 3
log /tmp/ovpn-a.log
EOF
cat > "$tmp_root/peer/ovpn-b.ovpn" <<'EOF'
client
dev ovpn-b
dev-type tun
proto tcp-client
remote 192.0.2.1 443
nobind
ca /tmp/ca.crt
cert /tmp/client-b.crt
key /tmp/client-b.key
remote-cert-tls server
data-ciphers AES-256-GCM:AES-128-GCM
auth SHA256
allow-compression no
verb 3
log /tmp/ovpn-b.log
EOF
scp "${peer_scp_args[@]}" "$tmp_root/peer/ovpn-a.ovpn" "$tmp_root/peer/ovpn-b.ovpn" admin@127.0.0.1:/tmp/
cat > "$tmp_root/peer-root-material.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

install -d -o root -g root -m 0700 /etc/wireguard/bastion-matrix
install -o root -g root -m 0600 /tmp/wg-client.key /etc/wireguard/bastion-matrix/a.key
install -o root -g root -m 0600 /tmp/wg-client-b.key /etc/wireguard/bastion-matrix/b.key
rm -f /tmp/wg-client.key /tmp/wg-client-b.key
for path in /tmp/ca.crt /tmp/client.crt /tmp/client.key /tmp/client-b.crt /tmp/client-b.key /tmp/server-wg.pub /tmp/ovpn-a.ovpn /tmp/ovpn-b.ovpn; do
  chown root:root "$path"
  chmod 0600 "$path"
done
EOF
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/peer-root-material.sh"
openvpn_started_before=$openvpn_started_after_config
ansible-playbook -i "$tmp_root/inventory.yml" "$tmp_root/playbooks/vpn.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars vpn_fixture_states="$tmp_root/public-states" --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$tmp_root/become-password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common" | tee "$tmp_root/idempotent-reapply.log"
rg -q 'bastion[[:space:]]*:.*changed=0.*failed=0' "$tmp_root/idempotent-reapply.log" || { echo 'vpn-vm-test: unchanged reapply was not idempotent' >&2; exit 1; }
openvpn_started_after=$(openvpn_active_enter)
test "$openvpn_started_after" = "$openvpn_started_before" || { echo 'vpn-vm-test: unchanged reapply restarted OpenVPN' >&2; exit 1; }
cat > "$tmp_root/assert-restored.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
test "$(readlink /var/lib/bastion/vpn/current)" = releases/valid
systemctl is-active --quiet bastion-vpn-apply.service openvpn-server@bastion.service
ip link show wg-bastion >/dev/null
EOF
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/assert-restored.sh"
cat > "$tmp_root/wg-lifecycle-server.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

action=${1:?lifecycle action is required}
runtime_root=/run/bastion-vpn
saved_secrets=/tmp/bastion-vpn-lifecycle-server.yaml
recovery_marker=$runtime_root/lifecycle-recovered

assert_cleaned() {
  ! systemctl is-active --quiet bastion-vpn-apply.service
  ! systemctl is-active --quiet openvpn-server@bastion.service
  ! ip link show wg-bastion >/dev/null 2>&1
  test ! -e "$runtime_root/active"
  test ! -e "$runtime_root/active.next"
}

case "$action" in
  stop)
    systemctl stop bastion-vpn-apply.service
    assert_cleaned
    echo VPN_VM_WG_LIFECYCLE_STOP_CLEANUP_PASS
    ;;
  restore-after-stop)
    /usr/local/libexec/bastion-vpn-apply-state
    systemctl is-active --quiet bastion-vpn-apply.service openvpn-server@bastion.service
    ip link show wg-bastion >/dev/null
    test -e "$runtime_root/active"
    echo VPN_VM_WG_LIFECYCLE_RESTORED_AFTER_STOP_PASS
    ;;
  failed-start)
    install -m 0600 /var/lib/bastion/secrets/openvpn-server-key "$saved_secrets"
    printf 'invalid synthetic key\n' > /var/lib/bastion/secrets/openvpn-server-key
    if systemctl restart bastion-secrets.service; then
      echo 'VPN_VM_WG_LIFECYCLE_FAIL: invalid persistent VPN key restart unexpectedly succeeded' >&2
      exit 1
    fi
    # The dependency failure has already stopped a working VPN.  Stage stale
    # state and start the apply unit: it fails before ExecStart and must still
    # run its non-reentrant stop-post cleanup.
    install -d -m 0700 "$runtime_root"
    ip link add wg-bastion type wireguard
    ln -s /var/lib/bastion/vpn/releases/valid "$runtime_root/active"
    ln -s /var/lib/bastion/vpn/releases/valid "$runtime_root/active.next"
    if systemctl start bastion-vpn-apply.service; then
      echo 'VPN_VM_WG_LIFECYCLE_FAIL: apply start unexpectedly succeeded' >&2
      exit 1
    fi
    assert_cleaned
    # SSH requires runtime secrets, so recover locally only after the peer has
    # a bounded 30-second interval to observe the denied data path.  The
    # lifecycle probe itself completes within two seconds; the longer interval
    # absorbs controller and QEMU scheduling before its follow-up starts.
    rm -f "$recovery_marker"
    systemd-run --quiet --collect \
      --unit=bastion-vpn-lifecycle-recovery --on-active=30s \
      --timer-property=AccuracySec=1s \
      /bin/bash -c '
      install -m 0600 "$1" /var/lib/bastion/secrets/openvpn-server-key
      rm -f "$1"
      systemctl restart bastion-secrets.service
      /usr/local/libexec/bastion-vpn-apply-state
      systemctl is-active --quiet bastion-vpn-apply.service openvpn-server@bastion.service
      ip link show wg-bastion >/dev/null
      test -e /run/bastion-vpn/active
      touch /run/bastion-vpn/lifecycle-recovered
    ' bash "$saved_secrets"
    echo VPN_VM_WG_LIFECYCLE_FAILED_START_CLEANUP_PASS
    ;;
  assert-recovered)
    test -e "$recovery_marker"
    systemctl is-active --quiet bastion-vpn-apply.service openvpn-server@bastion.service
    ip link show wg-bastion >/dev/null
    test -e "$runtime_root/active"
    rm -f "$recovery_marker" /run/bastion-vpn/lifecycle-recovery.log
    echo VPN_VM_WG_LIFECYCLE_RECOVERY_PASS
    ;;
  *)
    echo "VPN_VM_WG_LIFECYCLE_FAIL: unsupported action $action" >&2
    exit 2
    ;;
esac
EOF
run_wg_lifecycle_peer() {
  local expected=$1 marker=$2
  ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args "tests/vpn-vm-peer-matrix.sh --wg-lifecycle-probe $expected" | tee -a "$tmp_root/wg-lifecycle.log"
  rg -q "$marker" "$tmp_root/wg-lifecycle.log" || { echo "vpn-vm-test: WireGuard lifecycle marker missing: $marker" >&2; exit 1; }
}
run_wg_lifecycle_peer available VPN_VM_WG_LIFECYCLE_TRAFFIC_AVAILABLE
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/wg-lifecycle-server.sh stop" | tee -a "$tmp_root/wg-lifecycle.log"
rg -q 'VPN_VM_WG_LIFECYCLE_STOP_CLEANUP_PASS' "$tmp_root/wg-lifecycle.log" || { echo 'vpn-vm-test: explicit-stop cleanup marker missing' >&2; exit 1; }
run_wg_lifecycle_peer denied VPN_VM_WG_LIFECYCLE_TRAFFIC_DENIED
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/wg-lifecycle-server.sh restore-after-stop" | tee -a "$tmp_root/wg-lifecycle.log"
rg -q 'VPN_VM_WG_LIFECYCLE_RESTORED_AFTER_STOP_PASS' "$tmp_root/wg-lifecycle.log" || { echo 'vpn-vm-test: stop recovery marker missing' >&2; exit 1; }
run_wg_lifecycle_peer available VPN_VM_WG_LIFECYCLE_TRAFFIC_AVAILABLE
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/wg-lifecycle-server.sh failed-start" | tee -a "$tmp_root/wg-lifecycle.log"
rg -q 'VPN_VM_WG_LIFECYCLE_FAILED_START_CLEANUP_PASS' "$tmp_root/wg-lifecycle.log" || { echo 'vpn-vm-test: failed-start cleanup marker missing' >&2; exit 1; }
run_wg_lifecycle_peer denied VPN_VM_WG_LIFECYCLE_TRAFFIC_DENIED
run_wg_lifecycle_peer available VPN_VM_WG_LIFECYCLE_TRAFFIC_AVAILABLE
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/wg-lifecycle-server.sh assert-recovered" | tee -a "$tmp_root/wg-lifecycle.log"
rg -q 'VPN_VM_WG_LIFECYCLE_RECOVERY_PASS' "$tmp_root/wg-lifecycle.log" || { echo 'vpn-vm-test: recovery marker missing' >&2; exit 1; }
cat > "$tmp_root/start-firewall-listener.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

fixture=/run/bastion-vpn-firewall-listener.py
pidfile=/run/bastion-vpn-firewall-listener.pid
cat > "$fixture" <<'PY'
import selectors
import socket

selector = selectors.DefaultSelector()
# OpenVPN currently owns only IPv4 TCP/443. This IPv6-only fixture proves the
# firewall path and fails immediately if a future service already owns it.
for family, address, port in (
    (socket.AF_INET, "192.0.2.1", 18082),
    (socket.AF_INET6, "2001:db8:100::1", 18082),
    (socket.AF_INET6, "2001:db8:100::1", 443),
):
    listener = socket.socket(family, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if family == socket.AF_INET6:
        listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    listener.bind((address, port))
    listener.listen()
    listener.setblocking(False)
    selector.register(listener, selectors.EVENT_READ)
while True:
    for key, _ in selector.select():
        connection, _ = key.fileobj.accept()
        connection.close()
PY
nohup python3 "$fixture" >/run/bastion-vpn-firewall-listener.log 2>&1 </dev/null &
echo $! > "$pidfile"
sleep 1
ss -ltn4 | grep -q '192.0.2.1:18082'
ss -ltn6 | grep -q '\[2001:db8:100::1\]:18082'
ss -ltn6 | grep -q '\[2001:db8:100::1\]:443'
echo VPN_VM_FIREWALL_LISTENER_READY
EOF
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/start-firewall-listener.sh" | tee "$tmp_root/firewall-listener.log"
rg -q 'VPN_VM_FIREWALL_LISTENER_READY' "$tmp_root/firewall-listener.log" || { echo 'vpn-vm-test: temporary firewall listener was not ready' >&2; exit 1; }
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name file --args 'path=/tmp/bastion-vpn-keep-namespaces state=touch mode=0600'
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args tests/vpn-vm-peer-matrix.sh | tee "$tmp_root/peer-matrix.log"
rg -q 'VPN_VM_PEER_MATRIX_PASS' "$tmp_root/peer-matrix.log" || { echo 'vpn-vm-test: peer matrix marker missing' >&2; exit 1; }
rg -q 'VPN_VM_FIREWALL_INGRESS_PASS' "$tmp_root/peer-matrix.log" || { echo 'vpn-vm-test: firewall ingress marker missing' >&2; exit 1; }
cat > "$tmp_root/reload-firewall.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ufw reload >/dev/null
ufw status | grep -E '^Status: active$' >/dev/null
iptables-save | grep -E -- '-A POSTROUTING .*10\.42\.0\.0/24.*MASQUERADE' >/dev/null
ip6tables-save | grep -F 'ufw6-before-forward' >/dev/null
echo VPN_VM_UFW_RELOAD_PASS
EOF
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/reload-firewall.sh" | tee "$tmp_root/ufw-reload.log"
rg -q 'VPN_VM_UFW_RELOAD_PASS' "$tmp_root/ufw-reload.log" || { echo 'vpn-vm-test: UFW reload marker missing' >&2; exit 1; }
cat > "$tmp_root/seeded-isolation-server.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

table=bastion_vpn_seeded_isolation
flows=/run/bastion-vpn-seeded-isolation.flows
counters=/run/bastion-vpn-seeded-isolation.counters

interface_for() {
  case "$1" in
    wg-a|wg-b) printf '%s\n' wg-bastion ;;
    ovpn-a|ovpn-b) printf '%s\n' tun-openvpn ;;
    *) return 1 ;;
  esac
}

validate_flow() {
  local name=$1 family=$2 source_ns=$3 target_ns=$4 source=$5 target=$6 sport=$7 dport=$8
  case "$name:$source_ns:$target_ns" in
    wg-wg:wg-a:wg-b|ovpn-ovpn:ovpn-a:ovpn-b|wg-ovpn:wg-a:ovpn-b|ovpn-wg:ovpn-a:wg-b) ;;
    *) return 1 ;;
  esac
  [[ "$family" =~ ^[46]$ && "$sport" =~ ^2400[1-8]$ && "$dport" =~ ^2500[1-8]$ ]]
  if test "$family" = 4; then
    case "$source_ns:$source" in wg-a:10.43.0.2|ovpn-a:10.42.0.*) ;; *) return 1 ;; esac
    case "$target_ns:$target" in wg-b:10.43.0.3|ovpn-b:10.42.0.*) ;; *) return 1 ;; esac
  else
    case "$source_ns:$source" in wg-a:fd42:2::2|ovpn-a:fd42:1::*) ;; *) return 1 ;; esac
    case "$target_ns:$target" in wg-b:fd42:2::3|ovpn-b:fd42:1::*) ;; *) return 1 ;; esac
  fi
  test "$source" != "$target"
}

for_each_flow() {
  local callback=$1
  test -r "$flows"
  local count=0 name family source_ns target_ns source target sport dport
  while read -r name family source_ns target_ns source target sport dport; do
    validate_flow "$name" "$family" "$source_ns" "$target_ns" "$source" "$target" "$sport" "$dport" || return 1
    "$callback" "$name" "$family" "$source_ns" "$target_ns" "$source" "$target" "$sport" "$dport"
    count=$((count + 1))
  done < "$flows"
  test "$count" -eq 8
}

remove_flow() {
  local _=$1 family=$2 source_ns=$3 target_ns=$4 source=$5 target=$6 sport=$7 dport=$8 command
  command=iptables; test "$family" = 4 || command=ip6tables
  local input output
  input=$(interface_for "$source_ns")
  output=$(interface_for "$target_ns")
  "$command" -D FORWARD -i "$input" -o "$output" -s "$source" -d "$target" -p tcp --sport "$sport" --dport "$dport" -j ACCEPT
  "$command" -D FORWARD -i "$output" -o "$input" -s "$target" -d "$source" -p tcp --sport "$dport" --dport "$sport" -j ACCEPT
  ! "$command" -C FORWARD -i "$input" -o "$output" -s "$source" -d "$target" -p tcp --sport "$sport" --dport "$dport" -j ACCEPT
  ! "$command" -C FORWARD -i "$output" -o "$input" -s "$target" -d "$source" -p tcp --sport "$dport" --dport "$sport" -j ACCEPT
}

cleanup_flow() {
  remove_flow "$@" 2>/dev/null || true
}

clear_rules() {
  test -r "$flows" && for_each_flow cleanup_flow || true
  nft delete table inet "$table" 2>/dev/null || true
  rm -f "$counters"
}

cleanup() {
  clear_rules
  rm -f "$flows"
}

add_flow() {
  local name=$1 family=$2 source_ns=$3 target_ns=$4 source=$5 target=$6 sport=$7 dport=$8 command nfproto address_family
  command=iptables; nfproto=ipv4; address_family=ip
  test "$family" = 4 || { command=ip6tables; nfproto=ipv6; address_family=ip6; }
  local input output
  input=$(interface_for "$source_ns")
  output=$(interface_for "$target_ns")
  "$command" -I FORWARD 1 -i "$input" -o "$output" -s "$source" -d "$target" -p tcp --sport "$sport" --dport "$dport" -j ACCEPT
  "$command" -I FORWARD 1 -i "$output" -o "$input" -s "$target" -d "$source" -p tcp --sport "$dport" --dport "$sport" -j ACCEPT
  nft add rule inet "$table" forward iifname "$input" oifname "$output" meta nfproto "$nfproto" "$address_family" saddr "$source" "$address_family" daddr "$target" tcp sport "$sport" tcp dport "$dport" ct state established,related counter comment "seeded-$name-$family"
}

exact_counter() {
  local id=$1
  nft -a list chain inet "$table" forward | awk -v id="seeded-$id" '
    index($0, id) {
      for (i = 1; i <= NF; i++) if ($i == "packets") value = $(i + 1)
    }
    END { if (value != "") print value }
  '
}

snapshot_counter() {
  local name=$1 family=$2 _=$3
  local value
  value=$(exact_counter "$name-$family")
  [[ "$value" =~ ^[0-9]+$ && "$value" -ge 2 ]]
  printf '%s-%s %s\n' "$name" "$family" "$value" >> "$counters"
}

assert_counter() {
  local id=$1 before=$2 after
  after=$(exact_counter "$id")
  [[ "$after" =~ ^[0-9]+$ && "$after" -gt "$before" ]]
}

completed=0
trap 'test "$completed" = 1 || cleanup' EXIT
case "${1:?server seeded-isolation action is required}" in
  prepare)
    clear_rules
    for_each_flow ':'
    nft add table inet "$table"
    nft 'add chain inet bastion_vpn_seeded_isolation forward { type filter hook forward priority mangle; policy accept; }'
    for_each_flow add_flow
    completed=1
    ;;
  release)
    : > "$counters"
    for_each_flow snapshot_counter
    for_each_flow remove_flow
    completed=1
    ;;
  assert)
    while read -r id before; do assert_counter "$id" "$before"; done < "$counters"
    cleanup
    completed=1
    ;;
  cleanup)
    cleanup
    completed=1
    ;;
  *) echo "unsupported server seeded-isolation action: $1" >&2; exit 2 ;;
esac
EOF
chmod 0700 "$tmp_root/seeded-isolation-server.sh"
seeded_server_helper="$tmp_root/seeded-isolation-server.sh"
seeded_cleanup_ready=1
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --seeded-isolation-flows' | tee "$tmp_root/seeded-flows.log"
rg -q 'VPN_VM_SEEDED_ISOLATION_FLOWS_READY' "$tmp_root/seeded-flows.log" || { echo 'vpn-vm-test: seeded flow manifest is missing' >&2; exit 1; }
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name fetch --args "src=/tmp/bastion-vpn-seeded-isolation/flows dest=$tmp_root/seeded-isolation.flows flat=yes"
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name copy --args "src=$tmp_root/seeded-isolation.flows dest=/run/bastion-vpn-seeded-isolation.flows owner=root group=root mode=0600"
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$seeded_server_helper prepare"
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --seeded-isolation-establish' | tee -a "$tmp_root/seeded-isolation.log"
rg -q 'VPN_VM_SEEDED_ISOLATION_ESTABLISHED' "$tmp_root/seeded-isolation.log" || { echo 'vpn-vm-test: seeded TCP did not establish' >&2; exit 1; }
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$seeded_server_helper release"
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --seeded-isolation-release' | tee -a "$tmp_root/seeded-isolation.log"
rg -q 'VPN_VM_SEEDED_ISOLATION_PEER_PASS' "$tmp_root/seeded-isolation.log" || { echo 'vpn-vm-test: established seeded TCP was not dropped' >&2; exit 1; }
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$seeded_server_helper assert"
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --seeded-isolation-cleanup'
seeded_cleanup_ready=0
echo VPN_VM_SEEDED_ISOLATION_PASS | tee -a "$tmp_root/seeded-isolation.log"
rg -q 'VPN_VM_SEEDED_ISOLATION_PASS' "$tmp_root/seeded-isolation.log" || { echo 'vpn-vm-test: seeded isolation marker missing' >&2; exit 1; }

# Revoke client A locally, publish only the regenerated CRL/public release,
# and prove A's live tunnel is torn down while B remains/reconnects.
openssl ca -config "$tmp_root/peer/ca.cnf" -revoke "$tmp_root/peer/client.crt" -batch >/dev/null 2>&1
openssl ca -config "$tmp_root/peer/ca.cnf" -gencrl -out "$tmp_root/peer/revoked-crl.pem" -batch >/dev/null 2>&1
make_release revoked "$tmp_root/peer/revoked-crl.pem"
cp "$tmp_root/public-states/valid/wireguard/peers" "$tmp_root/public-states/revoked/wireguard/peers"
(cd "$tmp_root/public-states/revoked" && sha256sum openvpn/ca.crt openvpn/server.crt openvpn/crl.pem openvpn/metadata.json wireguard/peers > manifest.sha256)
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name copy --args "src=$tmp_root/public-states/revoked/ dest=/var/lib/bastion/vpn/releases/revoked/ owner=root group=root mode=0700 directory_mode=0700"
cat > "$tmp_root/activate-revoked.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ln -sfn releases/revoked /var/lib/bastion/vpn/current.next
mv -Tf /var/lib/bastion/vpn/current.next /var/lib/bastion/vpn/current
/usr/local/libexec/bastion-vpn-apply-state
systemctl is-active --quiet openvpn-server@bastion.service
EOF
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/activate-revoked.sh"
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --openvpn-lifecycle-probe revoked' | tee "$tmp_root/openvpn-revoke.log"
rg -q 'VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE' "$tmp_root/openvpn-revoke.log" || { echo 'vpn-vm-test: OpenVPN revoke marker missing' >&2; exit 1; }
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --openvpn-lifecycle-probe reconnect-b' | tee -a "$tmp_root/openvpn-revoke.log"
rg -q 'VPN_VM_OPENVPN_B_RECONNECTED' "$tmp_root/openvpn-revoke.log" || { echo 'vpn-vm-test: OpenVPN survivor reconnect marker missing' >&2; exit 1; }
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name reboot --args 'reboot_timeout=120'
ansible-playbook -i "$tmp_root/inventory.yml" "$tmp_root/playbooks/vpn.yml" --vault-password-file "$vault_password" --extra-vars vault_secrets_file=secrets/server.yaml --extra-vars vpn_fixture_states="$tmp_root/public-states" --extra-vars bastion_apply_final_ssh_policy=false --become-password-file "$tmp_root/become-password" --extra-vars "{\"ansible_ssh_common_args\":\"$ssh_common\"}" --ssh-common-args="$ssh_common" | tee "$tmp_root/openvpn-revoke-reapply.log"
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name command --args 'readlink /var/lib/bastion/vpn/current' | rg -q 'releases/revoked'
ansible -i "$tmp_root/peer-inventory.yml" all --become --become-method=ansible.builtin.su --become-password-file "$bootstrap_become_password" --ssh-common-args="$ssh_common" --module-name script --args 'tests/vpn-vm-peer-matrix.sh --openvpn-lifecycle-probe revoked' | tee -a "$tmp_root/openvpn-revoke.log"
rg -q 'VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE' "$tmp_root/openvpn-revoke.log" || { echo 'vpn-vm-test: OpenVPN revoke did not survive reboot/reapply' >&2; exit 1; }
cat > "$tmp_root/stop-firewall-listener.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

pidfile=/run/bastion-vpn-firewall-listener.pid
if test -r "$pidfile"; then
  kill "$(cat "$pidfile")" 2>/dev/null || true
fi
rm -f "$pidfile" /run/bastion-vpn-firewall-listener.py /run/bastion-vpn-firewall-listener.log
EOF
ansible -i "$tmp_root/inventory.yml" bastion_admin --user admin --become --become-method=ansible.builtin.su --become-password-file "$tmp_root/become-password" --ssh-common-args="$ssh_common" --module-name script --args "$tmp_root/stop-firewall-listener.sh"

echo 'VPN VM listener, idempotence and peer-matrix checks passed.'
