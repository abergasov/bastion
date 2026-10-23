# Tasks

Baseline: [server-platform](../../../specs/server-platform/spec.md).

## 1. Выбрать и проверить основу

- [x] 1.1 Проверить по официальным источникам поддерживаемый Ubuntu release, Ansible и нужные collections; записать версии, совместимость, sources и integrity checks для внешних artifacts.
- [x] 1.2 Сверить read-only Ansible источник с transition note; определить минимальные inventory/host inputs и перечень заменяемых NixOS файлов без переноса лишних ролей.
- [x] 1.3 Реализовать preflight адресов, OS/release, SSH host identity и bootstrap privileges до мутации; проверить invalid inputs, wrong host key и недостаточные права без изменений сервера.

## 2. Настроить платформу

- [x] 2.1 Добавить минимальные playbook/roles и Make entry point для Ubuntu без disk formatting/OS replacement; проверить initial apply на изолированной Ubuntu VM.
- [x] 2.2 Настроить persistent networking и native journal/log rotation на 30 дней, предоставив notifications место для auth log; проверить reboot и rotation без потери конфигурации.
- [x] 2.3 Добавить явный manual-maintenance path, отключить unattended upgrades/auto-reboot, записывать установленные версии; проверить отсутствие обновлений и рестартов при обычном повторном apply, partial-failure reporting при ошибке maintenance.
- [x] 2.4 Определить contract bootstrap → admin + su для следующего change; не оставлять routine root SSH и не передавать пароли аргументами.
- [x] 2.5 Заменить NixOS Make/scripts и operator docs на Ubuntu workflow, удалить заменённые NixOS config/tests/lock files; проверить ссылки и отсутствие вызываемого disk installer в новом пути. Историю OpenSpec сохранить.

## 3. Проверить и передать foundation

- [x] 3.1 Запустить formatting, syntax-check, ansible-lint и Ubuntu VM initial/repeated apply; unchanged inputs должны давать отсутствие ненужных changes/restarts. Проверить persistent state после reboot.
- [x] 3.2 Проверить provisioning и package update на fixture класса 1 vCPU/2 GB/20 GB, записать RAM/disk/swap и непроверенные ограничения; VPN throughput передать итоговому live checklist.
- [x] 3.3 Зафиксировать component evidence и unrun checks, передать contracts changes 2–5; не заявлять live deployment или готовность VPN.
