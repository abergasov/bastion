#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

role=roles/ssh_notifications
patch_file="$role/files/0001-bastion-runtime-config-retries-and-boot.patch"

test -f tests/fixtures/ssh-notify/auth.log
rg -q 'sshd\[4242\]: Accepted publickey for admin' tests/fixtures/ssh-notify/auth.log
test -f tests/fixtures/ssh-notify/auth-sshd-session.log
rg -q 'sshd-session\[1160\]: Accepted publickey for admin' tests/fixtures/ssh-notify/auth-sshd-session.log
sshd_session_record=$(<tests/fixtures/ssh-notify/auth-sshd-session.log)
rg -q '20d99f5050246dd450fbc57dfe4e44f1ae30e4bb' "$role/tasks/main.yml"
rg -q '1c87cd8a4e956237bcdd556e55dad16a771923287e543aea4fe215627c639828' "$role/tasks/main.yml"
rg -q 'SSH_NOTIFY_CONFIG=/run/secrets/bastion/ssh-notify.conf' "$role/templates/ssh-notify.service.j2" "$role/templates/ssh-notify-boot.service.j2"
rg -q '^PartOf=bastion-secrets.service$' "$role/templates/ssh-notify.service.j2"
rg -q '^PartOf=bastion-secrets.service$' "$role/templates/ssh-notify.service.j2"
rg -q 'Load controller-side Bastion server Vault' roles/secrets_administration/tasks/main.yml
rg -q 'ssh-notify.conf' roles/secrets_administration/templates/bastion-decrypt-secrets.sh.j2
rg -q 'rotate 30' roles/platform/tasks/main.yml
rg -q 'daily' roles/platform/tasks/main.yml
rg -q 'ssh_notifications' playbooks/bootstrap.yml playbooks/site.yml playbooks/maintenance.yml
rg -q 'maxNotificationAttempts = 6' "$patch_file"
rg -Fq 'func LogMessageAndWait(message string, additionalData ...string) error' "$patch_file"
rg -Fq 'func sendWithRetry(send func() error) error' "$patch_file"
rg -Fq 'case "message":' "$patch_file"
rg -Fq 'LogMessageAndWait(os.Args[2])' "$patch_file"
rg -Fq 'usage: ssh_notify message <message>' "$patch_file"
rg -q 'SSH_NOTIFY_TELEGRAM_API_URL' "$patch_file"
rg -Fq 'sshd(?:-session)?[[0-9]+]:.Accepted' "$patch_file"
rg -Fq 'TestSearchMatchRecognizesUbuntuSSHDSessionLogEntry' "$patch_file"
rg -Fq 'sshd-session[1160]: Accepted publickey for admin' "$patch_file"
rg -Fq "$sshd_session_record" "$patch_file"
! rg -q 'ssh notify service started' "$patch_file"
! rg -q 'ConditionFirstBoot' "$role/templates"
! rg -q 'ExecStartPost' "$role/templates"
! rg -q '/etc/ssh_notify.conf' "$role/templates"
! rg -q 'SSH_NOTIFY_TELEGRAM_API_URL' "$role/templates"

if test "${SSH_NOTIFY_SKIP_PACKAGE_TEST:-0}" = 1; then
  exit 0
fi

tmp_dir=$(mktemp -d /tmp/bastion-ssh-notify.XXXXXX)
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT
archive="$tmp_dir/source.tar.gz"
curl -fsSL --max-time 60 -o "$archive" https://github.com/abergasov/ssh_notify/archive/20d99f5050246dd450fbc57dfe4e44f1ae30e4bb.tar.gz
printf '%s  %s\n' '1c87cd8a4e956237bcdd556e55dad16a771923287e543aea4fe215627c639828' "$archive" | sha256sum --check --status
mkdir "$tmp_dir/source"
tar -xzf "$archive" -C "$tmp_dir/source" --strip-components=1
patch --batch --forward -p1 -d "$tmp_dir/source" -i "$root_dir/$patch_file"
rg -Fq 'replacement := "sshd[2]: Accepted publickey for new from 10.0.0.2 port 22\\n"' "$tmp_dir/source/internal/reader_test.go"
rg -Fq 'TestSearchMatchRecognizesUbuntuSSHDSessionLogEntry' "$tmp_dir/source/internal/reader_test.go"
rg -Fq "$sshd_session_record" "$tmp_dir/source/internal/reader_test.go"
(cd "$tmp_dir/source" && GOCACHE="$tmp_dir/go-cache" go test ./...)
(cd "$tmp_dir/source" && GOCACHE="$tmp_dir/go-cache" go build -trimpath -o "$tmp_dir/ssh_notify" ./cmd)
test -x "$tmp_dir/ssh_notify"
