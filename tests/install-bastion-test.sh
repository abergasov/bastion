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
cat > "$fake_bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = eval ]; then
  case "$*" in
    *sourceUser*) printf '%s' root ;;
    *ipv4Address*) printf '%s' 192.0.2.10 ;;
    *expectedEd25519HostKey*) printf '%s' 'ssh-ed25519 ZmFrZQ==' ;;
  esac
elif [ "$1" = run ]; then
  printf '%s\0' "$@" > "$NIXOS_ANYWHERE_ARGS"
  : > "$NIXOS_ANYWHERE_CALLED"
fi
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
chmod +x "$fake_bin/nix" "$fake_bin/ssh"

run_case() {
  local scenario=$1
  local marker="$tmp_dir/$scenario.called"
  local calls="$tmp_dir/$scenario.ssh-calls"
  local args="$tmp_dir/$scenario.nixos-anywhere-args"
  if PATH="$fake_bin:$PATH" HOST_INPUT="$input" NIXOS_ANYWHERE_CALLED="$marker" NIXOS_ANYWHERE_ARGS="$args" SSH_CALLS="$calls" SSH_RESULT="$scenario" "$root_dir/scripts/install-bastion"; then
    [ "$scenario" = ok ] || return 1
  else
    [ "$scenario" != ok ] || return 1
  fi
  [ ! -e "$marker" ] || [ "$scenario" = ok ]
  case "$scenario" in
    mismatch) [ "$(cat "$calls")" = 1 ] ;;
    no_privilege|ok) [ "$(cat "$calls")" = 2 ] ;;
  esac
  if [ "$scenario" = ok ]; then
    [ -s "$args" ]
    mapfile -d '' -t argv < "$args"
    known_hosts=${argv[10]#UserKnownHostsFile=}
    expected=(
      run .#nixos-anywhere --
      --flake .#bastion
      --target-host root@192.0.2.10
      --ssh-option BatchMode=yes
      --ssh-option "UserKnownHostsFile=$known_hosts"
      --ssh-option GlobalKnownHostsFile=/dev/null
      --ssh-option StrictHostKeyChecking=yes
    )
    [[ "${argv[10]}" == UserKnownHostsFile=/tmp/* ]]
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
run_case ok
