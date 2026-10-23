# Proposal

## Why

Владелец заменил NixOS на Ubuntu Server с настройкой через Ansible. Существующий
NixOS foundation не реализует новый [server-platform](../../../specs/server-platform/spec.md).
Нужен минимальный Ansible foundation поверх установленной Ubuntu без разметки диска.

## What Changes

- Добавить inventory/host inputs, playbook, необходимые зависимости и тонкую Make-цель.
- Проверять Ubuntu release, адреса, SSH host key и bootstrap privileges до мутаций.
- Настраивать базовую сеть, native logging/30-day retention и ручное обслуживание.
- Заменить действующие NixOS entry points и документацию; убрать неиспользуемые
  NixOS реализации и проверки после появления проверяемой Ubuntu замены.
- Проверить initial apply, повторный apply, reboot и ресурсы на Ubuntu fixture.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

Нет: реализует обновлённый baseline; `skip_specs: true`.

## Impact

Будущие Ansible inventory/playbook/roles, Makefile, installer scripts, tests и
operator docs. Источник — read-only `/home/alejandro/go/src/ansible`, см.
[границы переноса](../../../notes/ubuntu-ansible-transition.md). Завершённый архивный
`implement-nixos-platform` остаётся историей, его checkbox не переносятся.
Секреты/admin принадлежат следующему change. План не разрешает live deployment.
