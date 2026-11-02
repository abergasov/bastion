# Tasks

> Historical migration note: completed SOPS/age task wording is superseded by
> controller-only Ansible Vault and is no longer an active delivery contract.

## 1. Границы и совместимость

- [x] 1.1 Согласовать с `implement-ubuntu-platform` extension point его native 30-day retention/rotation policy для будущего text auth log и входной contract этого change, а с `implement-ubuntu-secrets-administration` — recipient и protected runtime-file interface; зафиксировать точки подключения без переноса общей SOPS plumbing, platform journal policy или plaintext в этот change и проверить контракт против [SSH login notifications](../../../specs/ssh-notifications/spec.md#requirement-ssh-login-notifications) и [pinned integration and runtime secrets](../../../specs/ssh-notifications/spec.md#requirement-pinned-integration-and-runtime-secrets).
- [x] 1.2 Проверить через upstream конкретные revision/build contract `ssh_notify` и фактические строки выбранного Ubuntu/OpenSSH auth log, включая rotation; сохранить representative sanitized fixtures и выполнить reader regression, прежде чем решать нужен ли compatibility patch по [SSH login notifications](../../../specs/ssh-notifications/spec.md#requirement-ssh-login-notifications).

## 2. Package и application delivery

- [x] 2.1 Добавить закреплённый Ansible-delivered artifact с source revision и hash; включить только подтверждённые local patches, не меняя внешний репозиторий, и проверить воспроизводимую сборку плюс отсутствие отдельного Bastion sender по [pinned integration and runtime secrets](../../../specs/ssh-notifications/spec.md#requirement-pinned-integration-and-runtime-secrets) и [application-owned notification delivery and retries](../../../specs/ssh-notifications/spec.md#requirement-application-owned-notification-delivery-and-retries).
- [x] 2.2 Если выбранная upstream-версия не выполняет policy delivery, добавить минимальный package patch, в котором `ssh_notify` сам делает initial send и максимум пять retries, прекращает их при успехе, безопасно сообщает exhaustion и продолжает следующий event; проверить Go regression с mock endpoint для immediate success, success during retry, шести неуспехов и последующего event по [application-owned notification delivery and retries](../../../specs/ssh-notifications/spec.md#requirement-application-owned-notification-delivery-and-retries).

## 3. Конфигурация и systemd

- [x] 3.1 Поставить полную конфигурацию `ssh_notify` как Ansible Vault ciphertext и controller-side Vault delivery в root-only persistent store с atomic runtime projection под `/run/secrets`; проверить, что service читает только этот файл, а Git, inventory/templates, task output/diffs, fact cache, journal fixtures и command arguments не содержат plaintext или credentials. Evidence: real ciphertext импортирован из approved legacy Vault через protected temporary storage; source Vault files остались неизменными; focused preflight/import/static/runtime tests passed. Isolated Ubuntu QEMU verification with synthetic Vault fixtures and a local mock endpoint passed (`SSH_NOTIFICATIONS_VM_PASS`); see [verification evidence](../../../../docs/verification.md). Live VPS and real Telegram delivery are not checked.
- [x] 3.2 Настроить native text SSH auth-log input и подключить его 30-day rotation к native policy `implement-ubuntu-platform`, затем добавить основной systemd service на Ubuntu с минимальным доступом к runtime config и этому log; в Ubuntu VM test выполнить свежий SSH login, rotation и следующий login через mock endpoint и проверить обработку по [SSH login notifications](../../../specs/ssh-notifications/spec.md#requirement-ssh-login-notifications).
- [x] 3.3 Добавить native systemd boot-trigger, который только при загрузке системы вызывает явный `ssh_notify` boot-event entry point; если выбранный upstream не имеет такого entry point, добавить минимальный local package patch, где `ssh_notify` формирует событие и доставляет его своим общим delivery path, и покрыть его mock-endpoint regression. В Ubuntu VM test отдельно перезагрузить VM и перезапустить только notification service, проверив boot/reboot message в первом случае и его отсутствие во втором по [explicit boot and reboot notifications](../../../specs/ssh-notifications/spec.md#requirement-explicit-boot-and-reboot-notifications).

## 4. Сквозная проверка

- [x] 4.1 Выполнить Ansible syntax/lint и artifact build и focused package tests, затем Ubuntu VM integration test с local mock endpoint для login, rotation, boot, service restart, immediate success, success during retries, exhaustion и последующей notification; сопоставить результаты со всеми сценариями [ssh-notifications](../../../specs/ssh-notifications/spec.md).
- [x] 4.2 Задокументировать фактически проверенные revision/log compatibility, package patches и неиспользование plaintext; явно отметить непроведённые deployment, live Telegram и recovery checks, без отправки реальных сообщений или изменения сервера.
