# Design

## Context

Цель — Ubuntu Server + Ansible, а в репозитории ещё остаётся NixOS foundation.
Реализация следует [server-platform](../../../specs/server-platform/spec.md).
Детали поддерживаемого релиза и зависимостей проверяются при реализации.

## Goals / Non-Goals

**Goals:** настройка готового Ubuntu VPS, проверяемый повторный запуск, ручные
обновления и небольшой provider-independent inventory.

**Non-Goals:** установка ОС, disk formatting, cloud API, framework для множества
хостов, перенос всего старого playbook, VPN membership или live rollout.

## Decisions

Владелец создаёт VPS с Ubuntu и своим public SSH key. Inventory содержит
адреса и bootstrap account, без секретов. Сначала проверяются host identity,
дистрибутив/версия и достаточные привилегии, затем применяются роли. Итоговый
переход на admin + password-authenticated su и его тесты принадлежат
`implement-ubuntu-secrets-administration`; routine playbook не сохраняет root SSH.

Используются Ansible modules и системные пакеты/службы Ubuntu. Versions Ansible
и используемых collections записываются; дополнительные collections добавляются
только по необходимости. Настройка без изменений не обновляет пакеты и не
рестартует службы. Native journal/log rotation покрывает 30 дней; notifications
подключает свой фактический auth log к этой политике.

Отдельный явно вызываемый maintenance path обновляет пакеты и конфигурацию.
Отключаются unattended upgrades и auto-reboot базового образа. Нет Nix closure
build, disk installer или обещания атомарного rollback. Частичный отказ update
отражается в результате, recovery использует согласованный путь пересоздания.

Существующие Make/scripts не объявляются Ubuntu-совместимыми переименованием.
Их замена и удаление ненужного NixOS-кода входят в реализацию с проверкой ссылок,
документации и тестов. Архивные OpenSpec artifacts сохраняются.

## Risks / Trade-offs

- Смена SSH/firewall может лишить доступа: сохранить текущую сессию, проверить
  свежий admin login перед отказом от bootstrap-доступа.
- Пакетные операции не атомарны: сообщать partial failure, не обещать общий downgrade.
- Check mode не доказывает работу: initial/repeated apply и reboot проверять в Ubuntu VM.

## Migration Plan

Сначала inventory/preflight и Ubuntu fixture, затем базовые роли и Make entry point,
после этого удаление заменённого NixOS tooling. Component checks передаются
следующим changes; готовность и live rollout оцениваются только после change 6.
