# Proposal

## Why

Ubuntu foundation требует настройки секретов и admin access через Ansible.
Историческая sops-nix реализация не предоставляет этот путь на Ubuntu.

## What Changes

- Перенести согласованную SOPS/age схему на Ansible-managed runtime decryption.
- Настроить admin-only key SSH, начальные admin/root passwords и повышение через su.
- Включить fail2ban с defaults выбранного Ubuntu package и проверить IPv4/IPv6.
- Предусмотреть безопасное использование нужных секретов из старого Ansible Vault.
- Проверить доступ, idempotence, recipient separation и secret lifecycle после reboot.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

Нет: реализует baseline [server-administration](../../../specs/server-administration/spec.md)
и [recovery-and-verification](../../../specs/recovery-and-verification/spec.md).

## Impact

Зависит от `implement-ubuntu-platform`. Затрагивает будущие роли accounts, SSH,
fail2ban, SOPS/runtime files, synthetic tests и operator docs. Предоставляет
секреты changes VPN и notifications; CA/client keys остаются локальными.
Архивный NixOS change не считается выполнением этого плана. Deployment не разрешён.
