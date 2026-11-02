# SSH notifications

`ssh_notifications` downloads source `abergasov/ssh_notify` revision
`20d99f5050246dd450fbc57dfe4e44f1ae30e4bb` and verifies archive SHA-256
`1c87cd8a4e956237bcdd556e55dad16a771923287e543aea4fe215627c639828` before
building it. There is no checkout and no Bastion sender, retry wrapper or queue.

The local package patch is deliberately limited to the required integration:
it reads `SSH_NOTIFY_CONFIG`, avoids logging the configured chat identifier,
retries one failed delivery at most five times, adds the explicit `boot` entry
point, and allows tests to replace the Telegram API URL through
`SSH_NOTIFY_TELEGRAM_API_URL`. Without that test-only environment variable it
uses the upstream Telegram URL. The sanitized representative records preserve
both the standard `sshd[PID]` form in `tests/fixtures/ssh-notify/auth.log` and
the Ubuntu `sshd-session[PID]` form in
`tests/fixtures/ssh-notify/auth-sshd-session.log`. The package reader regression
tests both forms. Upstream revision/build contract, package pin/hash/patch Go
tests and the trimmed build have passed.

The complete application configuration is one Ansible Vault value named
`ssh-notify-config` in `secrets/server.yaml`. Its decrypted content is written
only to `/run/secrets/bastion/ssh-notify.conf`, mode `0600`, by the existing
atomic runtime decryptor. It contains every `ssh_notify` setting, including the
Telegram settings; templates, inventory and Make arguments do not reconstruct
or contain it. The checked-in `secrets/server.yaml` is real controller-side
Vault ciphertext. Ansible delivers only protected persistent/runtime files; it
does not send Vault ciphertext or password to the VPS. This does not authorize
live Telegram delivery.

`ssh-notify.service` monitors `/var/log/auth.log`. Platform owns rsyslog's
daily 30-day rotation policy. `ssh-notify-boot.service` is independently enabled
at `multi-user.target`, invokes `ssh_notify boot`, and is not started by a
notification-service restart. Both units require the shared secrets service and
use the runtime configuration path; the main service additionally reads only the
authentication log.

The recorded verification is deliberately not a single harness result. An
initial synthetic Ubuntu VM full Ansible apply passed with `ok=59 changed=44
failed=0`. After correcting the reader, the role-only apply passed with `ok=18
changed=9 failed=0`, and its corrected reapply passed with `ok=15 changed=0
failed=0`. Ansible syntax and `ansible-lint` also passed.

The temporary tail check reported `SSH_NOTIFICATIONS_VM_TAIL_PASS`. It covered
an actual `sshd-session` SSH login, log rotation and the following login, mock
delivery with immediate success, success during retry, exhaustion and the next
event, an ordinary notification-service restart with no boot event, and a real
VM reboot with exactly one boot event. These are synthetic Ubuntu VM and local
mock-endpoint results, not a live-server or Telegram result.

Run `make ssh-notifications-test` for the pinned archive, patch application and
the upstream plus local mock-endpoint Go tests. It contacts GitHub only to fetch
that fixed archive and never contacts Telegram. `make test` runs only the static
notification wiring check. No deployment, live Telegram delivery, or recovery
test is evidence here.
