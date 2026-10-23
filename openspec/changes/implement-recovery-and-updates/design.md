# Design

## Context

См. [proposal.md](proposal.md). Ubuntu/Ansible implementation и её evidence ещё отсутствуют; исторические NixOS проверки не подтверждают новый baseline. Baseline
уже определяет поведение; этот change объединяет результаты platform, secrets,
VPN, lifecycle и notifications в один путь обновления, восстановления и
доказательства готовности.

## Goals / Non-Goals

**Goals:**

- Дать минимальные операторские процедуры для ручного update, reapply, reboot,
  recreation и recovery после компрометации.
- Сохранить authority локальных записей и запретить stale restore возвращать
  отозванный доступ.
- Определить сквозные автоматизированные проверки и отдельный future live
  checklist с проверяемыми свидетельствами.

**Non-Goals:**

- Автоматические обновления, autosync, отдельная система backup или новая
  подсистема restore.
- Первичная установка, реализация SOPS/age, VPN, membership, SSH или
  ssh_notify: ими владеют соседние changes.
- Реальное развертывание, перезагрузка VPS, отправка Telegram или проверка
  пользовательских приложений без отдельной явной авторизации.

## Decisions

### Один ручной путь обновления

Операторская инструкция после результатов `implement-ubuntu-platform` повторно
использует его Ansible maintenance workflow: review package/dependency changes,
syntax/lint и isolated integration checks, затем обновление пакетов и конфигурации
при сохранённой SSH-сессии и проверка нового входа SSH и обоих VPN. Ошибки
пакетных операций сообщаются как partial failure, без обещания atomic rollback. Критический security fix использует
тот же путь вне weekly window. Reboot выполняется вручную только когда он
требуется и повторяет эти проверки.

Это выполняет [ручные обновления](../../specs/server-platform/spec.md#requirement-manual-package-and-configuration-updates)
без отдельного updater. Поддерживаемое повторное применение прежней конфигурации
не заменяет runtime membership и перед открытием VPN не возвращает старые grants.
Произвольные package downgrades и атомарный откат ОС не гарантируются; при потере
доступа применяется recovery через пересоздание.

### Восстановление пересозданием с двумя причинами

При потере сервера или административного доступа оператор использует
installation workflow platform change для нового VPS, с проверкой его host key
и bootstrap privileges до изменения Ubuntu configuration; provisioning не форматирует диски. Для replacement создаются локально новый
OpenVPN server key/certificate и новые профили с единственным fingerprint;
старый ключ и сертификат не возвращаются. Новый VPS age recipient заменяет
старый в SOPS ciphertext, а WireGuard server key допускается сохранить только
если он не раскрыт. CA, client keys и authoritative records остаются локальными.

Для подтвержденного root compromise VPS пересоздаётся с новой age identity,
OpenVPN server certificate отзывается локально, а все секреты, доступные хосту,
включая server VPN keys, account-password material и ssh_notify configuration,
ротируются до повторного использования. CA/client keys меняются лишь при их
раскрытии. Замена recipient сама по себе не отзывает уже раскрытые секреты или
исторический ciphertext.

Разделение обычной потери и compromise предотвращает как избыточную замену
локальной CA, так и повторное применение доступных атакующему server secrets.
Конкретные вызовы и версии upstream проверяются при реализации, а не
фиксируются этим документом.

### Восстановление состояния не создаёт вторую authority

Local encrypted credential state остаётся единственной authority; GitHub даёт
только committed и pushed ciphertext. Перед публикацией любого recovered state
сверяется current local revocation record. При отсутствии такого record recovery
создаёт fresh trust material и явное re-enrollment, вместо применения старого
configuration revision, backup или repository revision. Потеря owner age key вместе с
decrypted local state требует новой owner identity и новых credentials; отдельный
backup key или автоматический push не добавляются.

Так сохраняются [revocations](../../specs/device-lifecycle/spec.md#requirement-revocations-survive-system-lifecycle-operations)
и [owner-only state](../../specs/recovery-and-verification/spec.md#requirement-owner-only-age-encryption-of-local-credential-state).
Альтернатива с восстановлением из configuration revision, старого ciphertext или
дополнительного backup-service отвергнута: она либо не доказывает актуальность
revocation, либо выходит за утвержденный scope.

### Сквозная проверка отделена от live-эксплуатации

После объединения changes 1–5 автоматизированный gate повторно использует их
component suites для platform, secrets, VPN, lifecycle и notifications, запускает
formatter, static checks, `ansible-playbook --syntax-check`, `ansible-lint` и idempotence checks. Этот change добавляет
только cross-component recovery scenarios: reapply/reboot, package updates, supported configuration restore,
recreation, stale restore, recipient separation, partial failures и отрицательные
проверки revoked identities.

Future live checklist запускается только после отдельного разрешения: он
сохраняет административную сессию во время rollout, проверяет fresh SSH, оба
endpoint, IPv4/IPv6 forwarding, IPv6 preference и IPv4 fallback, оба public DNS
через оба VPN, isolation, OpenVPN performance, profile fingerprint, log rotation,
notification service restart и actual reboot. Он фиксирует результат, exclusions
и unrun checks, не объявляя успешный Ansible run доказательством remote reachability. Проверки
на каждом пользовательском устройстве в checklist не входят.

Live recreation и compromise exercise остаются отдельными optional destructive
упражнениями после явной авторизации. Recovery покрывается обязательными VM/
integration scenarios; отсутствие production compromise drill не создаёт нового
blocker для readiness.

## Risks / Trade-offs

- [Старое состояние возвращает revoked credential] → перед listener activation
  reconcile с current local records; без них выпустить fresh trust material.
- [Компрометированный host secret повторно используется] → recreation, новый
  recipient и rotation всех host-accessible secret; не считать `sops updatekeys`
  достаточным recovery.
- [Неудачный update лишает SSH-доступа] → сохранить существующую сессию до
  fresh SSH check; после подтвержденной потери доступа применить recreation.
- [Успешный Ansible run ошибочно объявлен readiness] → хранить evidence отдельно для
  syntax/lint/idempotence/integration/live и явно отмечать непроведённые проверки.
- [Потеря owner key делает GitHub ciphertext бесполезным] → новая identity,
  fresh credentials и re-enrollment; дополнительный backup намеренно отсутствует.

## Migration Plan

1. После завершения changes 1–5 реализовать их contracts и operator docs,
   затем добавить интеграционный recovery/update workflow.
2. Выполнить Ansible syntax/lint/idempotence и Ubuntu VM/integration checks, сохранив evidence и
   невыполненные проверки.
3. Только после отдельной авторизации выполнить installation, update,
   recreation или live checklist. Если runtime state нельзя безопасно
   reconciliate, создать fresh trust material вместо rollback к старому grant.
