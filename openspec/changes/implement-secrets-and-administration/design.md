# Design

## Context

Базовые требования уже зафиксированы в
`openspec/specs/server-administration/spec.md` и
`openspec/specs/recovery-and-verification/spec.md`; этот change их реализует и
поэтому не содержит spec delta. В проекте ещё нет NixOS-конфигурации. Сначала
должен появиться каркас из `implement-nixos-platform`, после чего этот change
добавляет общие серверные секреты и административный доступ для следующих
changes.

## Goals / Non-Goals

**Goals:**

- Поставить единый минимальный путь для SOPS/age-секретов, доступных владельцу
  и VPS, с расшифровкой sops-nix только в защищённые runtime-файлы.
- Подготовить безопасное потребление серверных VPN-ключей, паролей `admin` и
  `root` и, позднее, целого зашифрованного файла ssh_notify.
- Реализовать публичный SSH только для `admin` по ключу, `su` с паролем `root`
  и fail2ban по политике SSH jail по умолчанию закреплённой ревизии.
- Оставить ясные границы для других changes: `implement-device-lifecycle`
  владеет owner-only CA, клиентскими ключами и выдачей; `implement-ssh-notifications`
  владеет plaintext-содержимым своего зашифрованного файла;
  `implement-recovery-and-updates` владеет ротацией и процедурами восстановления.

**Non-Goals:**

- Не создавать CA, клиентские ключи, записи выдачи или списки участников и не
  делать их доступными VPS.
- Не добавлять свой jail, пороги, исключения, allowlist исходных адресов,
  VPN-требование для SSH, sudo-путь или отдельный сервис управления секретами.
- Не выполнять установку, деплой, проверку на реальном VPS, ротацию либо
  восстановление в рамках этого change.

## Decisions

### Общая схема серверных секретов

Один SOPS/age-набор будет содержать только серверные материалы: VPN-ключи,
парольные материалы `admin`/`root` и, когда его добавит соседний change, полный
файл конфигурации ssh_notify. Для каждого такого секрета используются два
независимых получателя: владелец и VPS. Приватный ключ владельца остаётся вне
VPS и Git; приватный ключ VPS остаётся вне Git и `/nix/store`. В Git попадает
только шифротекст и открытые age recipients.

sops-nix будет единственным путём расшифровки на сервере: он создаёт защищённые
runtime-файлы, а модули и сервисы получают пути к ним без включения plaintext в
Nix-выражения, derivation, логи или аргументы команд. Владелец соответствующего
ресурса задаёт минимальные права чтения: учётные записи используют свои
password-файлы, а VPN/ssh_notify — только файлы, нужные конкретному сервису.
Конкретные опции выбранной стабильной NixOS и sops-nix для password-файлов,
runtime ownership и age identity должны быть сверены с первичными upstream
документами во время реализации; эта запись не утверждает их текущую форму.

Альтернатива — поместить все локальные и серверные секреты в один SOPS-файл —
отклоняется: CA и клиентские ключи не должны расшифровываться VPS. Отдельный
runtime-демон не нужен: native sops-nix уже даёт требуемый жизненный цикл.

### Bootstrap VPS age identity

До первой активации sops-nix этот change предоставляет минимальный provisioning
hook для независимой VPS age identity. Installer из `implement-nixos-platform`
только вызывает hook после authenticated source-OS SSH с проверкой host key;
он не владеет вторым bootstrap-решением. Hook создаёт или доставляет identity в
защищённый persistent path вне Git и `/nix/store`, получает его public recipient
и требует его проверки владельцем до включения VPS в SOPS ciphertext. Поэтому
первый запуск может расшифровать password material и server secrets без
временного plaintext в конфигурации.

Точный поддерживаемый API nixos-anywhere и sops-nix, механизм создания либо
доставки identity и формат подтверждения recipient должны быть сверены с
официальной документацией выбранной ревизии при реализации. Focused install
fixture с synthetic identity проверит, что identity доступна до первой
sops-nix activation, private identity не попадает в Git или `/nix/store`, а
ошибка проверки recipient останавливает дальнейшее secret provisioning.

Альтернатива — сгенерировать identity внутри первой NixOS activation —
отклоняется: до неё нельзя безопасно расшифровать необходимые account passwords
и server secrets.

### Разделение секретов и интерфейс для соседних changes

Интерфейс этого change ограничивается именами/путями серверных runtime-секретов
и административной политикой. Он не принимает и не описывает содержимое
owner-only age-хранилища устройства. `implement-vpn-connectivity` потребляет
пути к серверным ключам; `implement-ssh-notifications` добавляет собственный
зашифрованный config в установленный механизм без передачи Telegram-значений
через Nix; `implement-device-lifecycle` использует `admin` SSH с проверкой
host key и затем `su` к root.

Альтернатива — дать каждому change собственный SOPS bootstrap — отклоняется,
поскольку она размножает recipient management и упрощает ошибочную передачу
локальных секретов VPS.

### Учётные записи и SSH

Модуль создаёт `admin`, задаёт authorised key владельца и применяет секретные
password-файлы к `admin` и `root`. SSH остаётся публичным, но допускает только
`admin` с ключом; прямой вход root, password и keyboard-interactive методы
отключаются. Privilege elevation проходит через `su` и пароль root. Реализация
должна подтвердить, что выбранные NixOS-параметры сохраняют этот путь после
активации и не включают SSH password authentication как побочный эффект.

Альтернатива — выдавать root-доступ через sudo или временно разрешать root SSH —
отклоняется, так как это противоречит базовой административной модели.

### fail2ban без локальной политики

Модуль включает fail2ban и штатный SSH jail выбранного закреплённого
NixOS/nixpkgs без override порогов, окон, длительностей, repeat-offender
escalation или исключений. Конфигурация подключает jail к фактическому
источнику SSH-логов и действующему firewall. Focused проверки фиксируют
эффективные default values выбранной ревизии, проверяют matching и полный цикл
ban/unban отдельно для IPv4 и IPv6.

Альтернатива — записать числовые значения или собственный jail в проекте —
отклоняется: baseline требует defaults именно выбранной ревизии.

## Risks / Trade-offs

- [Неподходящие или изменившиеся upstream-опции NixOS/sops-nix] → до написания
  модулей сверить официальные option declarations и документацию закреплённой
  ревизии, затем покрыть выбранный путь evaluation и focused test.
- [VPS recipient получает лишний секрет] → проверить каждый SOPS input и
  расшифрованный runtime-каталог: CA, клиентские ключи и authoritative local
  records отсутствуют, а права сервисов минимальны.
- [Первая активация не имеет VPS age identity] → выполнить bootstrap через
  проверенный source-OS SSH до sops-nix и покрыть порядок synthetic install
  fixture; при неподтверждённом recipient не продолжать provisioning секретов.
- [fail2ban не видит фактический SSH-лог или не банит IPv6] → запустить
  отдельные IPv4/IPv6 попытки аутентификации, проверить журналы/jail и
  восстановление доступа после unban.
- [Изменение SSH/firewall лишает владельца доступа] → rollout сохраняет
  текущую административную сессию до проверки свежего login; согласованный
  fallback после потери доступа — recreation, а не console access.

## Migration Plan

1. После готовности `implement-nixos-platform` сверить upstream API выбранной
   закреплённой ревизии, добавить вызываемый installer hook для bootstrap VPS
   identity, затем минимальные модуль, encrypted fixtures и интерфейсы этого
   design.
2. Выполнить evaluation, build и focused NixOS checks в изолированной среде;
   проверить отсутствие plaintext в Git и build artifacts.
3. Перед любым авторизованным rollout подготовить зашифрованные реальные
   входы вне логов и аргументов, сохранить рабочую сессию и проверить новый SSH
   login до её закрытия.
4. Если rollout теряет доступ или проверка секретов не проходит, не объявлять
   готовность; применяется согласованная процедура recreation из
   `recovery-and-verification`, а ротация остаётся в
   `implement-recovery-and-updates`.

## Open Questions

- Точные option names, формат password material, ACL runtime-файлов и
  поддерживаемый API nixos-anywhere/sops-nix для bootstrap identity будут
  выбраны после проверки официальной документации выбранных NixOS, nixpkgs,
  sops-nix и fail2ban. Это не меняет установленные требования, схему recipients
  или границы задач.
