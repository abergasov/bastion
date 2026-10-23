# Design

## Context

См. [proposal.md](proposal.md). Ubuntu/Ansible implementation и проверки ещё отсутствуют; NixOS foundation сохранён как история. Baseline [ssh-notifications](../../specs/ssh-notifications/spec.md)
уже требует проверенную совместимость auth log, pinned artifact, полную SOPS-конфигурацию в
`/run/secrets`, отдельное определение загрузки и ограниченную доставку; это
change не меняет эти требования. `implement-ubuntu-platform` должен предоставить
Ubuntu/Ansible-фундамент, journal и native policy 30-day retention/rotation с местом для
text log. Этот change добавляет конкретный text SSH auth-log input и подключает
его ротацию к policy платформы, затем передаёт его `ssh_notify`; обратной
зависимости платформы от уведомлений нет. `implement-ubuntu-secrets-administration`
предоставляет recipient/runtime plumbing Ansible-managed SOPS.

## Goals / Non-Goals

**Goals:**

- Декларативно доставить одну закреплённую интеграцию `ssh_notify` с её
  конфигурацией только в защищённом runtime-файле.
- Проверить фактическую совместимость выбранных Ubuntu/OpenSSH и
  `ssh_notify` версии с log entry и ротацией; локально исправить только
  подтверждённое несовпадение.
- Обеспечить явное событие загрузки и bounded retry внутри `ssh_notify`.

**Non-Goals:**

- Изменять upstream `abergasov/ssh_notify`, отправлять реальные уведомления,
  добавлять очередь, sender/retry wrapper или гарантированную доставку.
- Менять wording SSH-уведомления, администрирование, VPN, выдачу устройств или
  общую SOPS/runtime-инфраструктуру соседнего change.

## Decisions

### Закреплённый package с локальными целевыми patches

Ansible доставляет artifact с фиксированными source revision и hash. До реализации
проверяются по upstream выбранная версия, её build contract и фактическая
совместимость строк Ubuntu/OpenSSH с reader; исторические сведения не заменяют
эту проверку. Если reader не принимает выбранный формат, upstream не
предоставляет entry point для явного boot event либо sender не выполняет policy
retries, patch включается только в Bastion package и содержит ровно
подтверждённую логику с regression test. Внешний репозиторий не меняется.

Это сохраняет воспроизводимость и не создаёт fork. Неприемлемы unpinned checkout
и самостоятельный Bastion sender: первый не воспроизводим, второй нарушает
владение генерацией и доставкой.

### Полная конфигурация одним Ansible-managed SOPS runtime-файлом

Этот change владеет содержимым единственного зашифрованного файла
`ssh_notify`, включая Telegram values и не-секретные application settings;
`implement-ubuntu-secrets-administration` владеет общим recipient и Ansible-managed SOPS
plumbing. Service получает только protected file под `/run/secrets`, читает его
на runtime и не собирает значения из tracked inventory/templates, Make arguments или переменных
командной строки. Unit запускается с минимально необходимым доступом к этому
файлу и выбранному text auth log.

Разделение на несколько секретов или генерация plaintext конфигурации в tracked Ansible templates отвергнуты:
они добавляют reconstruction path и риск plaintext в Git/task artifacts. Полная конфигурация
в ciphertext соответствует [pinned integration and runtime secrets](../../specs/ssh-notifications/spec.md#requirement-pinned-integration-and-runtime-secrets).

### Уведомление о boot создаёт только system boot trigger

Отдельный native systemd boot-trigger запускает явный entry point внутри
`ssh_notify` после достижения подходящей boot-фазы. Если выбранный upstream его
не предоставляет, минимальный local package patch добавляет этот entry point и
формирование boot event через тот же application-owned delivery path; systemd
только вызывает его. Запуск обязан явно передать контекст system boot, а обычный
service restart этого trigger не запускает. Проверка выполняется отдельно для
реальной перезагрузки и для restart основного service.

Startup notification самой службы не используется как признак reboot. Подход с
`ExecStartPost` основного unit отвергнут, потому что он срабатывает и при его
обычном restart.

### Bounded delivery остаётся в ssh_notify

Для одного уведомления отправитель выполняет initial attempt и до пяти retries,
немедленно прекращая попытки после первого успеха. После шести неуспехов он
записывает безопасный diagnostic, теряет только это уведомление и возвращается к
последующей обработке. Локальный patch покрывает immediate success, success on
retry, exhaustion и следующую notification через mock endpoint.

Durable queue и отдельный retry service отвергнуты: baseline явно не требует
eventual delivery и запрещает отдельный delivery mechanism.

## Risks / Trade-offs

- [Выбранный Ubuntu/OpenSSH log не совместим с reader] → зафиксировать
  representative actual entry в test fixture и добавить минимальный package
  patch только после воспроизводимого доказательства.
- [У upstream выбранной версии меняются build/API assumptions] → проверить
  revision, source и log behaviour до package pin; не утверждать совместимость
  на основании historical research.
- [Сбой Telegram теряет уведомление] → ограничить до шести attempts, записать
  diagnostic без credentials и продолжить следующий event; durable recovery
  намеренно отсутствует.
- [Права service шире необходимого] → проверить ownership/mode runtime config и
  log access в Ubuntu VM test, без plaintext в task output/diffs, fact cache, journal или args.

## Migration Plan

1. После готовности платформы и SOPS plumbing добавить package, ciphertext и
   service units; активировать только через будущую Ansible-конфигурацию.
2. Выполнить artifact build и Ansible syntax/lint и Ubuntu VM tests с mock endpoint: SSH login, ротация,
   boot, service restart и retry cases.
3. Реальное развёртывание, доставка Telegram и восстановление конфигурации сервера
   не входят в этот plan; их влияние на revocation и runtime state принадлежит
   `implement-recovery-and-updates`. Для package/config сохраняются только
   rollback considerations: прежний pinned package и encrypted configuration не
   должны требовать plaintext или ручной reconstruction.
