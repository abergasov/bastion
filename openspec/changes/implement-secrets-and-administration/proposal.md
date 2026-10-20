# Proposal

## Why

Базовые требования уже определяют защищённое хранение серверных секретов и
администрирование по SSH, но в репозитории пока нет NixOS-конфигурации, которая
их реализует. Нужен отдельный план минимальной общей инфраструктуры секретов и
административного доступа, чтобы последующие изменения VPN, жизненного цикла
устройств и уведомлений могли безопасно использовать её.

## What Changes

- Добавить NixOS-реализацию SOPS/age и sops-nix для серверных VPN-ключей и
  паролей `admin`/`root`: шифротекст хранится в Git, а расшифрованные файлы
  доступны только во время работы через защищённые runtime-файлы.
- Добавить bootstrap независимой VPS age identity до первой активации sops-nix:
  платформа вызывает минимальный provisioning hook через authenticated source-OS
  SSH с проверкой host key, а identity сохраняется вне Git и `/nix/store`.
- Настроить учётные записи, публичный ключ владельца, SSH только для `admin` по
  ключу и получение root-оболочки через `su` с паролем `root`.
- Включить fail2ban для публичного SSH с политикой jail по умолчанию выбранной
  закреплённой ревизии и подготовить проверку сопоставления логов и ban/unban для
  IPv4 и IPv6.
- Предоставить базовые интерфейсы секретов и административного доступа для
  изменений VPN, жизненного цикла устройств и SSH-уведомлений.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

Нет: изменение реализует существующие требования `server-administration` и
`recovery-and-verification`, не меняя наблюдаемое поведение этих спецификаций.

## Impact

Появятся NixOS-модули и зашифрованные шаблоны/метаданные секретов без
plaintext-значений, provisioning hook bootstrap VPS identity, а также focused
NixOS-проверки административного доступа и fail2ban. Изменение зависит от
`implement-nixos-platform`: installer вызывает принадлежащий этому change hook
без реализации второго secret bootstrap. Его интерфейсы секретов и SSH нужны
`implement-vpn-connectivity`,
`implement-device-lifecycle` и `implement-ssh-notifications`. Выдача
owner-only CA, клиентских ключей и записей остаётся в
`implement-device-lifecycle`; содержимое зашифрованной конфигурации
ssh_notify — в `implement-ssh-notifications`; ротация и восстановление — в
`implement-recovery-and-updates`.
