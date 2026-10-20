# Design

## Context

В проекте нет конфигураций, Make-целей, скриптов и тестов. Baseline уже задаёт
интерфейс управления, границу секретов, публичное состояние VPS, отзыв и
восстановление; этот change реализует эти требования без их изменения. См.
`proposal.md` и baseline [device-lifecycle](../../specs/device-lifecycle/spec.md),
[vpn-connectivity](../../specs/vpn-connectivity/spec.md),
[server-administration](../../specs/server-administration/spec.md) и
[recovery-and-verification](../../specs/recovery-and-verification/spec.md).

## Goals / Non-Goals

**Goals:**

- Локально создавать и хранить CA OpenVPN, серверные идентичности, ключи
  устройств, issuance и membership/revocation records.
- Сделать один последовательный путь изменения для add/revoke, который
  сохраняет owner-only ciphertext, публикует public-state и проверяет live-state.
- Дать Make-цели из baseline и экспорт профилей без обращения за private key к
  VPS.

**Non-Goals:**

- Новый сервис, база данных, очередь, веб-интерфейс, мультихостовый выбор или
  неинтерактивный revoke.
- Хранение CA/client private keys, owner age identity либо их ciphertext,
  расшифровываемого VPS, на сервере.
- Автоматические commit/push, развёртывание или проверка пользовательских VPN
  приложений.

## Decisions

### Одна локальная authority и отдельное публичное представление

Локальный рабочий credential state вне репозитория будет единственной authority:
он содержит CA, private keys, serial/issuance records и membership/revocation
records с owner-only permissions. После каждой мутации скрипт сохраняет его
age-ciphertext для единственного владельческого recipient в Git; private age key
остаётся в KeePassXC. Схема state и состав зашифрованного набора будут компактными
и versioned, но не требуют БД или постоянного процесса.

На VPS публикуется только root-owned runtime tree `/var/lib/bastion/vpn`.
Контракт с `implement-vpn-connectivity`: lifecycle атомарно публикует WireGuard
public key/address и OpenVPN CA, сертификаты, CRL и public metadata; VPN-сервисы
потребляют их без конкурирующего membership list. Точные protocol-пути и формат
выбираются при реализации вместе с fixture contract VPN change. «Public» здесь
описывает содержание, а не world-readable permissions.

Альтернатива — хранить membership в Nix-конфигурации или генерировать её на VPS —
отклонена: она смешивает authority, возвращает старое состояние generation и
требует доставлять CA/client secret на VPS.

### Локальная выдача и server identity

Выдача OpenVPN CA, сертификатов и CRL выполняется только на компьютере владельца
поддерживаемым PKI-инструментом, выбранным после проверки актуальной upstream
документации при реализации. Локально создаются ключи устройств и initial либо
replacement keypair каждого VPN-сервера. Private keys OpenVPN и WireGuard
серверов передаются только в отдельный SOPS/sops-nix поток
`implement-secrets-and-administration`; CA и client private keys в него не
попадают.
Export берёт current locally issued server certificate и формирует ровно один
`peer-fingerprint`; при отсутствии текущего сертификата или client private key
завершается без файла.

Альтернатива — выпускать либо восстанавливать CA/client keys на VPS — отклонена
требованиями разделения секретов. Выбор конкретной PKI-утилиты сейчас не
закрепляется неподтверждённым upstream предположением.

### Один критический путь мутации и восстановимая partial failure

Add/revoke берёт простой локальный advisory lock, сначала валидирует все входы,
создаёт staged records/artifacts и не перезаписывает существующий private key.
До удалённой публикации новая authority сохраняется атомарно как age ciphertext;
после этого скрипт доставляет staged public-state по SSH `admin` с проверкой host
key, поднимает привилегии через интерактивный `su` и atomically заменяет
root-owned runtime tree. Затем он применяет/перезагружает серверное состояние и
проверяет persistent и live результат. Пароли, токены и private keys не идут в
Make arguments, логи или удалённую командную строку.

При сбое до complete verification команда сообщает partial failure и оставляет
локальную authority пригодной для idempotent retry/reconciliation; успех возможен
только после ciphertext, persistent state и live state. Это намеренно избегает
двухфазного сервиса или очереди. Для WireGuard retry должен довести до одного
набора peer и в running interface, и в persistent source. Для OpenVPN retry
должен довести опубликованный CRL до running service; revoke кратко
перезапускает OpenVPN и проверяет отказ revoked client при работоспособности
non-revoked peer.

Альтернатива — считать успешной запись локального ciphertext либо отправку CRL —
отклонена, поскольку обе операции сами по себе не доказывают effective access
state.

### Узкий Make-интерфейс и local-only export

Makefile остаётся thin entry point к focused scripts. Он использует только
`VPN_HOST` и утверждённые цели `vpn-add-wg`, `vpn-add-open`, `vpn-list-wg`,
`vpn-list-open`, `vpn-export-wg`, `vpn-export-open`, `vpn-revoke-wg` и
`vpn-revoke-open`. Revoke выводит локальный список и принимает exact name; пустой
ввод, EOF, cancellation и unknown name завершаются до мутации. Export создаёт
owner-only, Git-ignored profile из локальных private keys; удаление файла профиля
не меняет revocation record.

Альтернатива — общий CLI, параметры `HOST`/`VPN` или client-name revoke —
отклонена baseline и увеличивает поверхность управления без потребности.

## Risks / Trade-offs

- [Сбой между ciphertext и VPS publish] → команда не сообщает успех; retry
  сверяет authority с persistent/live server state и публикует недостающее.
- [Сбой после публикации CRL] → revoke завершается partial failure, пока
  OpenVPN restart и отрицательное подключение revoked peer не проверены.
- [Старый generation, backup или restore] → VPN runtime state не живёт в
  generation; recovery до открытия listeners сверяет current local revocations,
  иначе использует fresh trust material.
- [Root на VPS скомпрометирован] → он может изменить admission, но не получает
  CA/client keys; восстановление и rotation остаются в change recovery.
- [Потерян local private state и age key] → GitHub ciphertext не восстановим;
  требуется fresh identity, explicit re-enrollment и новые profiles.

## Migration Plan

Это greenfield implementation без миграции существующих устройств. Перед первым
public-state publish скрипты проверят пустой или ожидаемый root-owned runtime
tree. Откат незавершённой операции выполняется повторным reconciliation из
последнего успешно расшифрованного authoritative state; старый Nix generation,
backup или ciphertext не используется как доказательство актуальных grants.
