#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

input="$tmp_dir/host-input.nix"
cat > "$input" <<'EOF'
{}
EOF

fake_bin="$tmp_dir/bin"
mkdir "$fake_bin"
recipient="age1$(printf 'q%.0s' {1..58})"
owner_recipient="age1$(printf 'r%.0s' {1..58})"
wrong_recipient="age1$(printf 'p%.0s' {1..58})"
cat > "$fake_bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = eval ]; then
  case "$*" in
    *sourceUser*) printf '%s' root ;;
    *ipv4Address*) printf '%s' 192.0.2.10 ;;
    *expectedEd25519HostKey*) printf '%s' 'ssh-ed25519 ZmFrZQ==' ;;
    *adminAuthorizedKey*)
      if [ "${INPUT_STATE:-ok}" != missing_admin ]; then
        printf '%s' 'ssh-ed25519 ZmFrZQ=='
      fi
      ;;
    *ownerAgeRecipient*) printf '%s' "$OWNER_AGE_RECIPIENT" ;;
    *vpsAgeRecipient*) printf '%s' "$VPS_AGE_RECIPIENT" ;;
    *vpsAgeIdentityFile*) printf '%s' "$VPS_AGE_IDENTITY_FILE" ;;
    *sopsSecretsFile*) printf '%s' secrets/server.yaml ;;
  esac
elif [ "$1" = run ]; then
  printf '%s\0' "$@" > "$NIXOS_ANYWHERE_ARGS"
  for ((i = 1; i <= $#; i++)); do
    if [ "${!i}" = --extra-files ]; then
      next=$((i + 1))
      extra_files=${!next}
      break
    fi
  done
  [ -n "${extra_files:-}" ]
  {
    stat -c '%a' "$extra_files"
    stat -c '%a' "$extra_files/var/lib/sops-nix/age/key.txt"
    cmp "$VPS_AGE_IDENTITY_FILE" "$extra_files/var/lib/sops-nix/age/key.txt"
  } > "$EXTRA_FILES_CHECK"
  : > "$NIXOS_ANYWHERE_CALLED"
fi
EOF
cat > "$fake_bin/sops" <<'EOF'
#!/usr/bin/env bash
if [ "${INPUT_STATE:-ok}" = missing_required_secret ] && [[ "$*" == *wireguard-server-key* ]]; then
  exit 1
fi
exit 0
EOF
cat > "$fake_bin/grep" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *'recipient:'* ]]; then
  [ "${INPUT_STATE:-ok}" != non_sops_metadata ] || exit 1
  if [ "${INPUT_STATE:-ok}" = missing_owner_recipient ] && [[ "$*" == *"$OWNER_AGE_RECIPIENT"* ]]; then
    exit 1
  fi
  exit 0
fi
exec /usr/bin/grep "$@"
EOF
cat > "$fake_bin/age-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = -y ]
[ "$2" = "$VPS_AGE_IDENTITY_FILE" ]
printf '%s\n' "${DERIVED_VPS_AGE_RECIPIENT:-$VPS_AGE_RECIPIENT}"
EOF
cat > "$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args=" $* "
[[ "$args" == *' BatchMode=yes '* ]]
[[ "$args" == *' UserKnownHostsFile='* ]]
[[ "$args" == *' GlobalKnownHostsFile=/dev/null '* ]]
[[ "$args" == *' StrictHostKeyChecking=yes '* ]]
for arg in "$@"; do
  case "$arg" in
    UserKnownHostsFile=*) known_hosts=${arg#UserKnownHostsFile=} ;;
  esac
done
[ -n "${known_hosts:-}" ]
grep -qx '192.0.2.10 ssh-ed25519 ZmFrZQ==' "$known_hosts"
call_file=${SSH_CALLS:?}
calls=$(cat "$call_file" 2>/dev/null || true)
calls=$((calls + 1))
printf '%s' "$calls" > "$call_file"
case "${SSH_RESULT:-ok}:$calls" in
  mismatch:*) exit 1 ;;
  no_privilege:1|ok:*) exit 0 ;;
  no_privilege:*) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/nix" "$fake_bin/ssh" "$fake_bin/age-keygen" "$fake_bin/sops" "$fake_bin/grep"

run_case() {
  local scenario=$1
  local marker="$tmp_dir/$scenario.called"
  local calls="$tmp_dir/$scenario.ssh-calls"
  local args="$tmp_dir/$scenario.nixos-anywhere-args"
  local extra_files_check="$tmp_dir/$scenario.extra-files-check"
  local identity="$tmp_dir/$scenario.age"
  printf '%s\n' "synthetic identity for $scenario" > "$identity"
  chmod 600 "$identity"
  local derived="$recipient"
  [ "$scenario" != recipient_mismatch ] || derived="$wrong_recipient"
  if PATH="$fake_bin:$PATH" HOST_INPUT="$input" NIXOS_ANYWHERE_CALLED="$marker" NIXOS_ANYWHERE_ARGS="$args" EXTRA_FILES_CHECK="$extra_files_check" SSH_CALLS="$calls" SSH_RESULT="$scenario" INPUT_STATE="$scenario" OWNER_AGE_RECIPIENT="$owner_recipient" VPS_AGE_RECIPIENT="$recipient" VPS_AGE_IDENTITY_FILE="$identity" DERIVED_VPS_AGE_RECIPIENT="$derived" "$root_dir/scripts/install-bastion"; then
    [ "$scenario" = ok ] || return 1
  else
    [ "$scenario" != ok ] || return 1
  fi
  [ ! -e "$marker" ] || [ "$scenario" = ok ]
  case "$scenario" in
    mismatch) [ "$(cat "$calls")" = 1 ] ;;
    no_privilege|recipient_mismatch|non_sops_metadata|missing_owner_recipient|missing_required_secret|ok) [ "$(cat "$calls")" = 2 ] ;;
    missing_admin) [ ! -e "$calls" ] ;;
  esac
  if [ "$scenario" = ok ]; then
    [ -s "$args" ]
    mapfile -d '' -t argv < "$args"
    extra_files_dir=${argv[6]}
    known_hosts=${argv[12]#UserKnownHostsFile=}
    [ "$(sed -n '1p' "$extra_files_check")" = 700 ]
    [ "$(sed -n '2p' "$extra_files_check")" = 600 ]
    [ "$(sed -n '3p' "$extra_files_check")" = '' ]
    expected=(
      run .#nixos-anywhere --
      --flake .#bastion
      --extra-files "$extra_files_dir"
      --target-host root@192.0.2.10
      --ssh-option BatchMode=yes
      --ssh-option "UserKnownHostsFile=$known_hosts"
      --ssh-option GlobalKnownHostsFile=/dev/null
      --ssh-option StrictHostKeyChecking=yes
    )
    [[ "${argv[12]}" == UserKnownHostsFile=/tmp/* ]]
    [ "${#argv[@]}" -eq "${#expected[@]}" ]
    for i in "${!expected[@]}"; do
      [ "${argv[i]}" = "${expected[i]}" ]
    done
  else
    [ ! -e "$args" ]
  fi
}

run_case mismatch
run_case no_privilege
run_case missing_admin
run_case recipient_mismatch
run_case non_sops_metadata
run_case missing_owner_recipient
run_case missing_required_secret
run_case ok
