#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d /tmp/bastion-server-crl.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT
state_root=$tmp_dir/state runtime_root=$tmp_dir/runtime libexec=$tmp_dir/libexec bin=$tmp_dir/bin
mkdir -p "$state_root/releases" "$runtime_root" "$libexec" "$bin" "$tmp_dir/lock"
chmod 0700 "$state_root" "$runtime_root"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$runtime_root/openvpn-ca-key" >/dev/null 2>&1
cp "$runtime_root/openvpn-ca-key" "$tmp_dir/ca.key"
openssl req -x509 -new -key "$runtime_root/openvpn-ca-key" -days 365 -subj /CN=synthetic-ca -out "$tmp_dir/ca.crt"
chmod 0600 "$runtime_root/openvpn-ca-key"
mkdir -p "$tmp_dir/ca/newcerts"
printf '1000\n' > "$tmp_dir/ca/serial"; printf '1000\n' > "$tmp_dir/ca/crlnumber"; : > "$tmp_dir/ca/index.txt"
cat > "$tmp_dir/ca/openssl.cnf" <<EOF
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = $tmp_dir/ca
database = \$dir/index.txt
new_certs_dir = \$dir/newcerts
certificate = $tmp_dir/ca.crt
private_key = $runtime_root/openvpn-ca-key
serial = \$dir/serial
crlnumber = \$dir/crlnumber
default_md = sha256
default_crl_days = 30
policy = policy_any
[ policy_any ]
commonName = supplied
EOF
openssl ca -batch -config "$tmp_dir/ca/openssl.cnf" -gencrl -out "$tmp_dir/crl.pem" >/dev/null 2>&1

release="$state_root/releases/release-1"
mkdir -p "$release/openvpn" "$release/wireguard"
cp "$tmp_dir/ca.crt" "$release/openvpn/ca.crt"; cp "$tmp_dir/crl.pem" "$release/openvpn/crl.pem"
printf 'R\t261101000000Z\t261001000000Z\t01\tunknown\t/CN=revoked-client\n' > "$release/openvpn/index.txt"
printf 'SERVER\n' > "$release/openvpn/server.crt"
printf '%s\n' '{"membership_revision":1,"crl_sequence":4096}' > "$release/openvpn/metadata.json"
printf 'peers\n' > "$release/wireguard/peers"
ln -s releases/release-1 "$state_root/current"

cat > "$libexec/bastion-vpn-verify-state" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp_dir/verify.log"
openssl crl -in "\$(readlink -f "$state_root/current")/openvpn/crl.pem" -noout >/dev/null 2>&1 || exit 1
readlink -f "$state_root/current"
EOF
chmod 0700 "$libexec/bastion-vpn-verify-state"
cat > "$bin/stat" <<EOF
#!/usr/bin/env bash
if test "\${1:-}" = -c && test "\${2:-}" = "%U:%G:%a" && test "\${3:-}" = "$runtime_root/openvpn-ca-key"; then
  printf 'root:root:%s\\n' "\$(/usr/bin/stat -c %a "\$3")"
else
  exec /usr/bin/stat "\$@"
fi
EOF
cat > "$bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
if test "${SYSTEMCTL_FAIL:-0}" = 1; then exit 1; fi
exit 0
EOF
cat > "$bin/ssh_notify" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_LOG"
test "${NOTIFY_FAIL:-0}" = 1 && exit 1
EOF
chmod 0700 "$bin/stat" "$bin/systemctl" "$bin/ssh_notify"
cp "$bin/ssh_notify" "$libexec/ssh_notify"
chmod 0700 "$libexec/ssh_notify"

sed -e "s#/var/lib/bastion/vpn#$state_root#g" \
    -e "s#/run/secrets/bastion/openvpn-ca-key#$runtime_root/openvpn-ca-key#g" \
    -e "s#/run/lock#$tmp_dir/lock#g" \
    -e "s#/run/lock/bastion-vpn-state.lock#$tmp_dir/state.lock#g" \
    -e "s#/usr/local/libexec/bastion-vpn-verify-state#$libexec/bastion-vpn-verify-state#g" \
    -e "s#/usr/local/libexec/ssh_notify#$libexec/ssh_notify#g" \
    -e 's#chown -R root:root "\$next"#:#' \
    "$root_dir/roles/vpn/files/bastion-vpn-renew-crl" > "$tmp_dir/renew"
chmod 0700 "$tmp_dir/renew"
export PATH="$bin:$PATH" SYSTEMCTL_LOG="$tmp_dir/systemctl.log" NOTIFY_LOG="$tmp_dir/notify.log"
: > "$SYSTEMCTL_LOG"; : > "$NOTIFY_LOG"
run_renew() { "$tmp_dir/renew" "$@"; }
status_value() { python3 - "$state_root/crl-status.json" "$1" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))[sys.argv[2]])
PY
}

# Expiring/offline renewal signs with the matching public CA and preserves revoked index.
openssl ca -batch -config "$tmp_dir/ca/openssl.cnf" -gencrl -crl_lastupdate 20000101000000Z -crl_nextupdate 20000102000000Z -out "$release/openvpn/crl.pem" >/dev/null 2>&1
run_renew --reconcile
rg -qx -- '--allow-expired' "$tmp_dir/verify.log"
test "$(status_value crl_sequence)" -gt 4096
test "$(cat "$(readlink -f "$state_root/current")/openvpn/index.txt")" = "$(cat "$release/openvpn/index.txt")"
openssl crl -in "$(readlink -f "$state_root/current")/openvpn/crl.pem" -noout -verify -CAfile "$tmp_dir/ca.crt" >/dev/null
! rg -Fq 'BEGIN PRIVATE KEY' "$state_root"

# A valid CRL is a no-op and must not invoke activation.
: > "$SYSTEMCTL_LOG"; run_renew; test ! -s "$SYSTEMCTL_LOG"

# Missing or stale bookkeeping reconstructs status without re-signing a valid CRL.
unchanged=$(readlink -f "$state_root/current"); rm "$state_root/crl-status.json"
run_renew; test "$(readlink -f "$state_root/current")" = "$unchanged"
python3 - "$state_root/crl-status.json" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path))
value["membership_revision"] = 0
open(path, "w").write(json.dumps(value))
PY
run_renew; test "$(readlink -f "$state_root/current")" = "$unchanged"

# Reconcile is persistent and sequence numbers increase on each signed run.
old_sequence=$(status_value crl_sequence); run_renew --reconcile
test "$(status_value crl_sequence)" -gt "$old_sequence"

# Missing and incorrectly protected keys fail and record failure status.
rm "$runtime_root/openvpn-ca-key"; if "$tmp_dir/renew" --reconcile; then exit 1; fi
test "$(status_value result)" = failed
cp "$tmp_dir/ca.key" "$runtime_root/openvpn-ca-key"; chmod 0644 "$runtime_root/openvpn-ca-key"
if "$tmp_dir/renew" --reconcile; then exit 1; fi; test "$(status_value result)" = failed

# Notifier failure is ignored; a later attempt still reaches the signer.
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$runtime_root/openvpn-ca-key" >/dev/null 2>&1
chmod 0600 "$runtime_root/openvpn-ca-key"; export NOTIFY_FAIL=1
if "$tmp_dir/renew" --reconcile; then exit 1; fi
if "$tmp_dir/renew" --reconcile; then exit 1; fi
test "$(wc -l < "$NOTIFY_LOG")" -ge 2
test "$(status_value notification_failed)" = True
test -n "$(status_value reason)"
export NOTIFY_FAIL=0; cp "$tmp_dir/ca.key" "$runtime_root/openvpn-ca-key"; chmod 0600 "$runtime_root/openvpn-ca-key"

# Failed activation leaves pending state for a retry.
export SYSTEMCTL_FAIL=1
if "$tmp_dir/renew" --reconcile-and-activate; then exit 1; fi
test "$(status_value activation_pending)" = True
test -s "$SYSTEMCTL_LOG"
: > "$SYSTEMCTL_LOG"
export SYSTEMCTL_FAIL=0; run_renew --activate; test -s "$SYSTEMCTL_LOG"
! rg -Fq -- '--no-block' "$SYSTEMCTL_LOG"
test "$(status_value result)" = activated
test "$(status_value activation_pending)" = False
python3 - "$state_root/crl-status.json" "$(readlink -f "$state_root/current")" <<'PY'
import json
import subprocess
import sys
from datetime import datetime, timezone

status = json.load(open(sys.argv[1]))
release = sys.argv[2]
metadata = json.load(open(release + "/openvpn/metadata.json"))
value = subprocess.check_output(["openssl", "crl", "-in", release + "/openvpn/crl.pem", "-noout", "-nextupdate"], text=True).strip().split("=", 1)[1]
expiry = int(datetime.strptime(value, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc).timestamp())
assert status["membership_revision"] == metadata["membership_revision"]
assert status["crl_sequence"] == metadata["crl_sequence"]
assert status["next_update"] == expiry
PY

# A publisher must reject an interleaving current-release swap after validation.
publish_root=$tmp_dir/publish-state publish_libexec=$tmp_dir/publish-libexec
mkdir -p "$publish_root/releases/old" "$publish_root/releases/new" "$publish_libexec"
printf '{"version":2,"membership_revision":1,"crl_sequence":1,"openvpn_clients":[],"revocations":[]}\n' > "$publish_root/releases/old/metadata.json"
printf '{"version":2,"membership_revision":2,"crl_sequence":2,"openvpn_clients":[],"revocations":[]}\n' > "$publish_root/releases/new/metadata.json"
ln -s releases/old "$publish_root/current"
cat > "$publish_libexec/verify" <<EOF
#!/usr/bin/env bash
readlink -f "$publish_root/current"
ln -sfn releases/new "$publish_root/current"
EOF
cat > "$publish_libexec/apply" <<EOF
#!/usr/bin/env bash
touch "$tmp_dir/publisher-applied"
EOF
chmod 0700 "$publish_libexec/verify" "$publish_libexec/apply"
publisher=$tmp_dir/publisher-race archive=$tmp_dir/.bastion-vpn-release-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.tar
touch "$archive"
sed -e "s#/var/lib/bastion/vpn#$publish_root#g" \
    -e "s#/run/lock/bastion-vpn-state.lock#$tmp_dir/publisher.lock#g" \
    -e "s# /run/lock# $tmp_dir#g" \
    -e "s#/home/admin/.bastion-vpn-release-#$tmp_dir/.bastion-vpn-release-#g" \
    -e "s#/usr/local/libexec/bastion-vpn-verify-state#$publish_libexec/verify#g" \
    -e "s#/usr/local/libexec/bastion-vpn-apply-state#$publish_libexec/apply#g" \
    "$root_dir/roles/vpn/files/bastion-vpn-publish-state" > "$publisher"
chmod 0700 "$publisher"
if "$publisher" "$archive"; then exit 1; fi
test "$(readlink -f "$publish_root/current")" = "$publish_root/releases/new"
test ! -e "$tmp_dir/publisher-applied"

# The renewal-only verifier admits the expired real CRL above, but never a fake CRL.
bad_release=$state_root/releases/bad
cp -a "$(readlink -f "$state_root/current")" "$bad_release"
printf 'not a CRL\n' > "$bad_release/openvpn/crl.pem"
ln -sfn releases/bad "$state_root/current"
if run_renew --reconcile; then exit 1; fi

# Static contracts: persistent timer, no remain-after-exit, and boot ordering.
rg -q '^Persistent=true$' roles/vpn/templates/bastion-vpn-renew-crl.timer.j2
! rg -q '^RemainAfterExit=' roles/vpn/templates/bastion-vpn-renew-crl.service.j2
rg -q '^      Requires=bastion-vpn-renew-crl.service$' roles/vpn/tasks/main.yml
rg -q '^      After=bastion-secrets.service bastion-vpn-renew-crl.service$' roles/vpn/tasks/main.yml
rg -q 'next_update=.*openssl crl' roles/vpn/files/bastion-vpn-apply-state-once
rg -q '"result": "activated"' roles/vpn/files/bastion-vpn-apply-state-once
rg -q '"activation_pending": False' roles/vpn/files/bastion-vpn-apply-state-once
printf '%s\n' 'server CRL renewal synthetic checks passed'
