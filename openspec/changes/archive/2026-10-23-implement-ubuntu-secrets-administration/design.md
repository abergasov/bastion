# Design

## Context

Сохраняются owner/VPS SOPS recipients и owner-only age credential state.
Ansible Vault в старом проекте — источник разрешённого импорта, не новая схема
хранения Bastion. См. [transition](../../../notes/ubuntu-ansible-transition.md).

## Goals / Non-Goals

**Goals:** безопасное provision/reapply секретов, admin access и проверяемая
защита SSH на Ubuntu.

**Non-Goals:** перенос private SSH key/seed на VPS, хранение там CA/client keys,
смена требований VPN, автоматический import всех secrets или live rollout.

## Decisions

На компьютере владельца нужные значения читаются из Vault в защищённой рабочей
области вне репозитория и сохраняются в SOPS/age ciphertext. Vault password не
копируется в Bastion/Git/VPS. Новая OpenVPN identity создаётся локально независимо
от разрешения переиспользовать другие секреты. Для проверок используются synthetic values.

Ansible доставляет ciphertext и независимую VPS age identity с root-only доступом.
SOPS runtime decryption под systemd выполняется перед зависимыми службами при
apply и каждой загрузке, создаёт защищённые файлы под `/run/secrets`; отсутствие
ключа, ошибка decrypt или неполные secrets не разрешают старт со stale данными.
Использовать существующие SOPS/systemd средства, без отдельного secrets framework.
Owner age identity и CA/client state никогда не поставляются на VPS.

Secret tasks используют `no_log: true` и `diff: false`; plaintext не сохраняется
в facts/cache/debug output. Секреты не подставляются в shell/Make args. Полная
ssh_notify config имеет отдельный ciphertext, но общий runtime contract;
содержимым конфигурации владеет notifications change.

Bootstrap создаёт admin и устанавливает owner-supplied admin/root password hashes.
Hash material стабильно между reruns: повторный запуск не меняет salt/пароль.
После проверки sshd configuration и свежего admin login итоговая политика
запрещает root/другие SSH accounts, password и keyboard-interactive auth.
Routine Ansible подключается как admin с host verification, поднимает привилегии
через password-authenticated `su`. Проверить это на выбранной версии Ansible.
Не переносить passwordless sudo или server-side private-key restoration.

fail2ban использует default SSH jail policy установленного Ubuntu package.
Записываются effective defaults; подключаются фактические логи и firewall.
Старый `jail.local` с overrides не копируется.

## Risks / Trade-offs

- Неверный порядок SSH changes блокирует доступ: validate до reload и проверка
  fresh admin connection при сохранённой рабочей сессии.
- Runtime secrets исчезают при reboot: проверить boot ordering и отказ
  dependent services при decrypt failure.
- Root на VPS читает его секреты: это не защита от полного host compromise;
  recovery меняет VPS identity и exposed secrets.

## Migration Plan

После platform contract реализовать SOPS runtime, затем accounts/SSH/fail2ban.
Переносить реальные секреты только при необходимости реализации, не в fixtures.
Передать VPN/notifications защищённые file paths и Ubuntu test fixtures.
