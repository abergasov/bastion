#!/usr/bin/env bash
# Prepare the reusable, synthetic base used by the disposable QEMU suites.
# It deliberately contains no repository, Vault, VPN or notification secrets.
set -euo pipefail

assets=${BASTION_VM_ASSETS:-/tmp/bastion-vm-assets}
image_name=ubuntu-26.04-server-cloudimg-amd64.img
image_url=https://cloud-images.ubuntu.com/releases/resolute/release/$image_name
image_sha256=5645d0318ad21f643ebb1ac4567514620e9893380b07b0201fda163baa5b7eb5
image=$assets/$image_name
base=$assets/resolute-lifecycle.qcow2
key=$assets/id_ed25519
known_hosts=$assets/known_hosts-lifecycle
password=$assets/bootstrap-password
stamp=$assets/.fixture-version
fixture_version=ubuntu-26.04-resolute-fixture-v1

require() { command -v "$1" >/dev/null || { echo "prepare-vm-fixture: missing $1" >&2; exit 2; }; }
for tool in curl qemu-img qemu-system-x86_64 ssh ssh-keygen ssh-keyscan python3 openssl sha256sum; do require "$tool"; done

install -d -m 0700 "$assets"
if test -f "$stamp" && test "$(<"$stamp")" = "$fixture_version"; then
  for path in "$image" "$base" "$key" "$key.pub" "$known_hosts" "$password"; do
    test -r "$path" || { echo "prepare-vm-fixture: incomplete cached fixture: $path" >&2; exit 1; }
  done
  test "$(stat -c %a "$key")" = 600
  test "$(stat -c %a "$password")" = 600
  test -s "$known_hosts"
  echo "VM_FIXTURE_READY=$assets"
  exit 0
fi

if test -e "$base" || test -e "$key" || test -e "$known_hosts" || test -e "$password"; then
  echo "prepare-vm-fixture: fixture files exist without the expected version marker; refuse to replace $assets" >&2
  exit 2
fi

download=$assets/$image_name.download
checksum_ok() {
  test -f "$1" && printf '%s  %s\n' "$image_sha256" "$1" | sha256sum --check --status
}
preserve_unverified_image() {
  local candidate="$image.unverified-$(date -u +%Y%m%d%H%M%S)"
  while test -e "$candidate"; do candidate="$candidate-1"; done
  mv "$image" "$candidate"
  echo "prepare-vm-fixture: preserved unverified cached image as $candidate" >&2
}

# A previous interrupted builder may already have a complete, verified file at
# either temporary path.  Promote it only after verifying its full checksum.
if ! checksum_ok "$image"; then
  if test -f "$image"; then preserve_unverified_image; fi
  if checksum_ok "$download"; then
    mv "$download" "$image"
  else
    shopt -s nullglob
    for candidate in "$image".unverified-*; do
      if checksum_ok "$candidate"; then
        mv "$candidate" "$image"
        break
      fi
    done
    shopt -u nullglob
  fi
fi

if ! checksum_ok "$image"; then
  # Keep partial downloads on every failure: curl -C - makes a later builder
  # resume this exact file, while checksum failure never promotes it to image.
  curl -fL -C - --retry 3 --connect-timeout 20 --max-time 1800 -o "$download" "$image_url"
  if ! test -f "$download"; then
    echo "prepare-vm-fixture: download did not leave a resumable file: $download" >&2
    exit 1
  fi
  if ! checksum_ok "$download"; then
    echo "prepare-vm-fixture: incomplete or invalid download preserved at $download" >&2
    exit 1
  fi
  mv "$download" "$image"
fi
checksum_ok "$image" || {
  echo "prepare-vm-fixture: official image checksum mismatch: $image" >&2
  exit 1
}

work=$(mktemp -d /tmp/bastion-vm-fixture.XXXXXX)
chmod 0700 "$work"
vm_pid=''
http_pid=''
cleanup() {
  status=$?
  if test "$status" -ne 0; then
    echo "VM_FIXTURE_FAILURE_EVIDENCE=$work" >&2
    echo "VM_FIXTURE_SERIAL=socat - UNIX-CONNECT:$work/console.sock" >&2
    echo "VM_FIXTURE_MONITOR=socat - UNIX-CONNECT:$work/monitor.sock" >&2
    echo "VM_FIXTURE_LOG=$work/qemu.log" >&2
    if test -n "$vm_pid" && kill -0 "$vm_pid" 2>/dev/null; then
      echo "prepare-vm-fixture: QEMU remains running for local diagnostic console access" >&2
    fi
    trap - EXIT
    exit "$status"
  fi
  test -z "$vm_pid" || kill "$vm_pid" 2>/dev/null || true
  test -z "$http_pid" || kill "$http_pid" 2>/dev/null || true
  test -z "$vm_pid" || wait "$vm_pid" 2>/dev/null || true
  test -z "$http_pid" || wait "$http_pid" 2>/dev/null || true
  rm -rf "$work"
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT
umask 077
ssh-keygen -q -t ed25519 -N '' -f "$work/id_ed25519"
openssl rand -hex 24 > "$work/bootstrap-password"
chmod 600 "$work/bootstrap-password"
password_value=$(<"$work/bootstrap-password")
http_port=$((38000 + RANDOM % 2000))

cat > "$work/meta-data" <<'EOF'
instance-id: bastion-synthetic-fixture-v1
local-hostname: bastion-fixture
EOF
# NoCloud requests these companion documents in addition to user-data.  Keep
# vendor data empty and leave the QEMU user-mode NIC on DHCP; neither file
# contains fixture credentials or other sensitive material.
: > "$work/vendor-data"
cat > "$work/network-config" <<'EOF'
version: 2
ethernets:
  qemu-user:
    match:
      name: "en*"
    dhcp4: true
    dhcp6: false
EOF
cat > "$work/user-data" <<EOF
#cloud-config
users:
  - name: admin
    gecos: Synthetic Bastion Administrator
    primary_group: admin
    groups: [adm, sudo]
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - $(<"$work/id_ed25519.pub")
ssh_pwauth: false
disable_root: true
chpasswd:
  expire: false
  list: |
    root:$password_value
    admin:$password_value
EOF

python3 -m http.server "$http_port" --bind 0.0.0.0 --directory "$work" >"$work/http.log" 2>&1 &
http_pid=$!
qemu-img create -f qcow2 -F qcow2 -b "$image" "$work/base.qcow2" >/dev/null
qemu-system-x86_64 -machine accel=tcg -m 1024 -smp 1 \
  -drive "file=$work/base.qcow2,if=virtio,format=qcow2" \
  -smbios "type=1,serial=ds=nocloud-net;s=http://10.0.2.2:$http_port/" \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:38222-:22 -device virtio-net-pci,netdev=n0 \
  -display none \
  -chardev "socket,id=console,path=$work/console.sock,server=on,wait=off,logfile=$work/serial.log,logappend=on" \
  -serial chardev:console \
  -monitor "unix:$work/monitor.sock,server,nowait" >"$work/qemu.log" 2>&1 &
vm_pid=$!

for _ in $(seq 1 180); do
  ssh-keyscan -T 2 -p 38222 127.0.0.1 > "$work/known_hosts" 2>/dev/null || true
  if test -s "$work/known_hosts" && ssh -F /dev/null -i "$work/id_ed25519" -p 38222 -o BatchMode=yes -o ConnectTimeout=3 \
    -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$work/known_hosts" -o StrictHostKeyChecking=yes \
    admin@127.0.0.1 true >/dev/null 2>&1; then
    break
  fi
  kill -0 "$vm_pid" 2>/dev/null || { tail -n 80 "$work/qemu.log" >&2; exit 1; }
  sleep 1
done
ssh -F /dev/null -i "$work/id_ed25519" -p 38222 -o BatchMode=yes -o ConnectTimeout=3 \
  -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$work/known_hosts" -o StrictHostKeyChecking=yes \
  admin@127.0.0.1 'sudo -S -p "" -k true' < "$work/bootstrap-password" >/dev/null
ssh -F /dev/null -i "$work/id_ed25519" -p 38222 -o BatchMode=yes -o ConnectTimeout=3 \
  -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$work/known_hosts" -o StrictHostKeyChecking=yes \
  admin@127.0.0.1 'sudo -n systemctl poweroff' >/dev/null || true
for _ in $(seq 1 90); do
  kill -0 "$vm_pid" 2>/dev/null || { wait "$vm_pid" 2>/dev/null || true; vm_pid=''; break; }
  sleep 1
done
test -z "$vm_pid" || { echo 'prepare-vm-fixture: guest did not shut down cleanly' >&2; exit 1; }

install -m 0600 "$work/id_ed25519" "$key"
install -m 0644 "$work/id_ed25519.pub" "$key.pub"
install -m 0644 "$work/known_hosts" "$known_hosts"
install -m 0600 "$work/bootstrap-password" "$password"
mv "$work/base.qcow2" "$base"
printf '%s\n' "$fixture_version" > "$stamp"
chmod 600 "$stamp"
echo "VM_FIXTURE_READY=$assets"
