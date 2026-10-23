# Tasks

Baseline: [server-administration](../../../specs/server-administration/spec.md),
[recovery-and-verification](../../../specs/recovery-and-verification/spec.md).

Post-review corrections and boot/reboot regression evidence (2026-10-23):
[verification record](../../../../docs/verification.md#secrets-regression-verification--2026-10-23).

## 1. Runtime secrets

- [x] 1.1 Проверить поддерживаемые SOPS/age и Ansible su interfaces по актуальным первичным источникам; записать версии и native runtime contract для Ubuntu.
- [x] 1.2 Реализовать owner/VPS recipient validation, protected VPS identity/ciphertext delivery и SOPS runtime decryption до служб при apply/boot; тестировать wrong recipient, absent identity, corrupt ciphertext, incomplete secrets и невозможность старта со stale secrets.
- [x] 1.3 Проверить synthetic recipient separation: owner и VPS независимо decrypt server secrets, VPS не decrypt CA/client state; restrictive permissions, no_log/diff suppression, отсутствие plaintext в Git, artifacts, facts, args и failure/check-mode output.
- [x] 1.4 Документировать безопасный import нужных значений из read-only старого Vault в SOPS/age; проверить synthetic import без утечки, переноса Vault password/SSH seed или изменения источника. Реальные значения копировать только по необходимости реализации, не в тесты.

## 2. Administration

- [x] 2.1 Создать admin, установить owner-supplied стабильные admin/root password hashes и только public SSH key; проверить initial/repeated apply без замены hash и без private SSH key на VPS.
- [x] 2.2 Настроить и validate admin-only SSH key auth, отказ root/other users/password/keyboard-interactive; сохранить bootstrap session до fresh admin verification, проверить routine Ansible admin + su с верным и неверным root password.
- [x] 2.3 Настроить fail2ban SSH с defaults выбранного Ubuntu package и фактическим logging/firewall backend; записать defaults, проверить matching и ban/unban отдельно для IPv4/IPv6 без старых policy overrides.

## 3. Verification и передача

- [x] 3.1 Запустить syntax-check, ansible-lint, focused regressions и Ubuntu VM tests для SSH/su, fail2ban, secrets permissions, reboot и idempotence; явно записать unrun checks.
- [x] 3.2 Передать VPN/notifications согласованные runtime paths и synthetic fixtures, обновить operator docs; не объявлять Ubuntu deployment или live readiness на основании исторических NixOS checks.
