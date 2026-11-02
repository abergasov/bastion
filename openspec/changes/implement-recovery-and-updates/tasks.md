# Tasks

> Server CRL renewal decision (2026-11-01): the VPS receives a protected CA
> signing key. Earlier CA-preserving compromise-recovery decisions and checked
> tests below apply only to the old controller-only CA boundary. Fresh-CA recovery
> for the new boundary is implemented with synthetic regression coverage in
> [fix-review-findings task 1.7](../fix-review-findings/tasks.md). Disposable-VM
> renewal checks (1.6) and combined verification (2.1) remain open; earlier
> results do not establish readiness for server-side renewal.

> Historical migration note: completed SOPS/age references are superseded by
> controller-only Ansible Vault and are not operative tasks.

## 1. Описать ручное обслуживание

- [x] 1.1 После готовности `implement-ubuntu-platform` добавить операторскую процедуру weekly и critical update, повторно использующую его native commands: review package/dependency changes, syntax/lint и isolated checks, Ansible update/apply, сохранение SSH-сессии, fresh SSH и оба VPN; проверить platform evidence и failure fixture, что failed update сообщает partial changes и recovery steps без ложного успеха (требование: [ручные обновления](../../specs/server-platform/spec.md#requirement-manual-package-and-configuration-updates)).
- [x] 1.2 Добавить в ту же процедуру ручной reboot только при необходимости и post-reboot SSH/VPN checks; проверить документационным review и evidence platform suite, что reboot не запускается unattended и failure отмечается без ложного readiness (требования: [ручные обновления](../../specs/server-platform/spec.md#requirement-manual-package-and-configuration-updates), [safe rollout](../../specs/recovery-and-verification/spec.md#requirement-safe-rollout-within-authorized-scope)).
- [x] 1.3 Реализовать безопасное поддерживаемое повторное применение прежней конфигурации через существующий platform workflow, без гарантии package downgrade и без замены runtime membership; проверить Ubuntu VM test, что восстановление конфигурации не возвращает revoked WireGuard peer или OpenVPN client (требования: [revocations survive lifecycle](../../specs/device-lifecycle/spec.md#requirement-revocations-survive-system-lifecycle-operations), [automation and integration verification](../../specs/recovery-and-verification/spec.md#requirement-automation-and-integration-verification)).

## 2. Реализовать recovery без второй authority

- [x] 2.1 Добавить operator runbook для обычной потери VPS или административного доступа, который повторно использует installation workflow platform change, verified new host key и existing secret/lifecycle contracts; проверить документационным review, что он не требует console/rescue access или старый VPN server key (требование: [recovery through recreation](../../specs/recovery-and-verification/spec.md#requirement-recovery-through-server-recreation)).

  Evidence: [операторская процедура](../../../docs/recovery.md), документационный
  review 2026-10-24: повторно используются installation и secret/lifecycle
  contracts, проверяется новый host key; console/rescue, аварийный root-пароль
  и прежний VPN server key не являются prerequisites. Неактуальные revocations
  требуют fresh trust material и re-enrollment. На дату этого review задачи
  2.2–2.4 и integration/live checks ещё не были завершены; актуальные результаты
  приведены ниже. В том review сервер и секреты не изменялись.

- [x] 2.2 Встроить в recreation новый локально выпущенный OpenVPN server key/certificate, новый VPS age recipient через существующий SOPS workflow и replacement profiles с единственным новым `peer-fingerprint`; проверить integration fixture, что прежний fingerprint и OpenVPN identity не публикуются, а сохранение WireGuard server key возможно только для non-compromise path (требования: [recovery through recreation](../../specs/recovery-and-verification/spec.md#requirement-recovery-through-server-recreation), [encrypted server VPN keys](../../specs/recovery-and-verification/spec.md#requirement-encrypted-server-vpn-keys-in-git)).
- [x] 2.3 Добавить recovery preflight, который перед публикацией состояния получает current authoritative revocations от lifecycle contract; при их отсутствии требует fresh trust material и explicit re-enrollment; проверить Ubuntu VM/integration test со stale configuration и старым ciphertext, что revoked credentials остаются denied (требования: [owner-only state](../../specs/recovery-and-verification/spec.md#requirement-owner-only-age-encryption-of-local-credential-state), [revocations survive lifecycle](../../specs/device-lifecycle/spec.md#requirement-revocations-survive-system-lifecycle-operations)).
- [x] 2.4 Добавить обработку потери owner age key вместе с decrypted local state: создать новую owner identity, fresh credentials и replacement profiles без попытки расшифровать GitHub ciphertext; проверить isolated fixture, что VPS recipient не может прочесть owner-only state и прежние credentials не получают access (требование: [owner-only state](../../specs/recovery-and-verification/spec.md#requirement-owner-only-age-encryption-of-local-credential-state)).

## 3. Обработать подтверждённую компрометацию

- [x] 3.1 Добавить отдельную compromise procedure, которая пересоздаёт VPS, заменяет его age identity, локально отзывает exposed OpenVPN server certificate и вызывает rotation всех host-accessible server VPN, account-password и ssh_notify secrets; проверить Ubuntu VM/integration scenario, что одна замена recipient не считается recovery и plaintext не попадает в args/logs (требования: [recovery after host compromise](../../specs/recovery-and-verification/spec.md#requirement-recovery-after-host-compromise), [persistent credential state](../../specs/recovery-and-verification/spec.md#requirement-persistent-credential-state-and-protected-secrets)).
- [x] 3.2 Документировать и проверить ветвление exposure: local CA/client keys сохраняются при VPS-only compromise и заменяются только при подтверждённом local exposure; проверить тестовую матрицу, что replacement profiles pin only new server certificate в обеих ветвях (требования: [recovery after host compromise](../../specs/recovery-and-verification/spec.md#requirement-recovery-after-host-compromise), [OpenVPN profile fingerprint](../../specs/vpn-connectivity/spec.md#requirement-openvpn-profile-server-fingerprint)).
- [x] 3.3 Добавить явные operator responsibilities для импорта replacement profile, удаления старого auto-connect, disconnect старых sessions и проверки identity в выбранном приложении; проверить review документации, что это не заявлено как автоматизация или обязательная per-device acceptance check (требования: [recovery through recreation](../../specs/recovery-and-verification/spec.md#requirement-recovery-through-server-recreation), [user-owned applications](../../specs/vpn-connectivity/spec.md#requirement-user-owned-applications-and-device-configuration)).

  Evidence: [операторская инструкция](../../../docs/profile-replacement.md),
  документационный review 2026-10-24: все четыре действия описаны как ручные;
  автоматическое обновление доверия и обязательная per-device acceptance
  явно исключены. Выпуск профилей, recovery и проверки приложений не выполнялись.

## 4. Завершить обязательное автоматизированное cross-component evidence

- [x] 4.1 После готовности changes 1–5 переиспользовать их component-suite evidence для platform, secrets, VPN, lifecycle и notifications; добавить только cross-component Ubuntu VM/integration scenario recovery с protocol-compatible test peers и проверить initial/repeated Ansible apply и Ubuntu VM suite (требования: [automation and integration verification](../../specs/recovery-and-verification/spec.md#requirement-automation-and-integration-verification), [server connectivity verification](../../specs/recovery-and-verification/spec.md#requirement-server-connectivity-and-live-operation-verification)).

  Evidence: prerequisite `implement-ssh-notifications` завершён; его
  disposable Vault/QEMU suite с синтетической полной `ssh_notify`
  configuration завершился `SSH_NOTIFICATIONS_VM_PASS`
  (`/tmp/bastion-ssh-notifications-vm.GnGUuj`): initial apply
  `ok=57 changed=40 failed=0`, repeated apply `ok=50 changed=0 failed=0`,
  fresh notification и reboot checks прошли. Cross-component initial role run
  (`/tmp/bastion-recovery-cross-component.ZYnnCk`) затем потребовал только
  fixture directory-mode correction; its COW continuation
  (`/tmp/bastion-cross-final-diagnose.Awz873`) passed repeated apply
  `ok=69 changed=0 failed=0`, fresh SSH local mock, reboot four services
  (secrets, WireGuard, OpenVPN, notifications) и boot notification mock.
  Independent lifecycle suite завершился
  `DEVICE_LIFECYCLE_VM_PASS` (`/tmp/bastion-device-lifecycle-vm.HjEosN`):
  initial `ok=44 changed=27 failed=0`, replacement `ok=39 changed=3 failed=0`,
  compromise `ok=39 changed=5 failed=0`; add/export/revoke, fingerprint,
  root-password rotation и graceful shutdown проверены. VPN initial apply
  (`/tmp/bastion-vpn-vm.Y0msLO`) дал `ok=44 changed=27 failed=0`, а repeated
  apply — `ok=37 changed=0 failed=0`. После узких fixture fixes retained
  continuation (`/tmp/bastion-vpn-continuation.yRKOCa`) завершилась
  `VPN_VM_CONTINUATION_PASS`: peer matrix и firewall ingress прошли, revoked A
  fresh denial/B active и B reconnect прошли до reboot, а после actual reboot
  (67 s) и reapply `ok=37 changed=1 failed=0` fresh revoked A denial/B active
  прошли снова. Это documented continuation, а не заявление о single
  uninterrupted runner. Никакие synthetic checks не authorise live VPS или
  Telegram.
- [x] 4.2 Расширить только cross-component scenario позитивными и негативными recovery cases: reboot/reapply, package updates, supported configuration restore, recreation, missing/invalid/expired CRL, stale restore, recipient separation и partial failure между local/server state; проверить, что каждый case сохраняет denied state revoked identity либо сообщает partial failure без success (требования: [automation and integration verification](../../specs/recovery-and-verification/spec.md#requirement-automation-and-integration-verification), [effective OpenVPN revocation](../../specs/device-lifecycle/spec.md#requirement-effective-openvpn-revocation), [authenticated and consistent mutations](../../specs/device-lifecycle/spec.md#requirement-authenticated-and-consistent-mutations)).

  Evidence 2026-10-26: disposable Ubuntu/QEMU continuation preserved the
  already-completed package-maintenance run and then used the same updated
  server with a fresh synthetic peer. `TEST_ETHERNET_SOCKET_CONNECTED`,
  `VPN_VM_OPENVPN_B_RECONNECTED`,
  `VPN_VM_OPENVPN_REVOKED_A_FRESH_DENIED_B_ACTIVE`,
  `VPN_VM_WG_LIFECYCLE_TRAFFIC_DENIED` and `REBOOT_SERVICES_PASS` passed
  against the immutable pre-maintenance revoked `resume-*-6fd954e4` profiles.
  Package-version record, automatic boot/application of persisted public state
  and graceful power-off were checked. A previous forcibly interrupted
  disposable overlay had zero-byte `READY`/manifest and correctly failed
  closed; it was repaired explicitly by republishing the complete public
  release from retained current owner authority before this continuation. This
  is historical synthetic evidence only; it neither authorizes deployment nor
  alters section 5 exclusions.
- [x] 4.3 Выполнить formatter, relevant static checks, `ansible-playbook --syntax-check`, `ansible-lint` и initial/repeated apply после integration changes; сохранить результаты отдельно от live evidence и явно перечислить exclusions/unrun checks (требование: [automation and integration verification](../../specs/recovery-and-verification/spec.md#requirement-automation-and-integration-verification)).

  Evidence 2026-10-25: explicit-age lifecycle suite — 32 tests; recovery static
  gate passed; syntax-check bootstrap/site/maintenance, production ansible-lint
  (14 files) and strict OpenSpec validation passed. Disposable Ubuntu/QEMU
  scenario `DEVICE_LIFECYCLE_VM_PASS` (`/tmp/bastion-device-lifecycle-vm.p6B7eY`)
  covered initial and repeated apply, stale refusal, replacement fingerprint,
  compromise rotation, revoked-denial/CRL and protected root-password rotation.
  This is synthetic VM evidence only: live VPS, Telegram delivery and sections
  5.1–5.2 remain unrun.

## 5. Проверить live readiness после отдельной авторизации

Пункт 5.1 обязателен перед объявлением сервера готовым; готовность кода и
автоматизированных проверок из раздела 4 сама по себе его не заменяет.
Пункт 5.2 — необязательное разрушительное упражнение, а не условие готовности.

- [ ] 5.1 После отдельной явной авторизации выполнить live update/reboot на VPS resource class и записать package-update evidence, memory, disk headroom, throughput, swap, fresh SSH, оба VPN endpoint, IPv4/IPv6 forwarding, IPv6 preference и IPv4 fallback, оба DNS через оба VPN, isolation, OpenVPN performance, log rotation, notification service restart и actual reboot notification; не заявлять о поведении пользовательских приложений (требования: [small VPS resource target](../../specs/server-platform/spec.md#requirement-small-vps-resource-target), [server connectivity verification](../../specs/recovery-and-verification/spec.md#requirement-server-connectivity-and-live-operation-verification)).
- [ ] 5.2 После отдельной явной авторизации при необходимости выполнить live recreation и отдельно согласованный destructive compromise exercise без реальных секретов в logs/arguments; зафиксировать replacement Ansible Vault ciphertext, rotation evidence и current profile fingerprints. Это optional exercise, а не новый blocker readiness: required recovery evidence остаётся в разделе 4 (требования: [recovery through recreation](../../specs/recovery-and-verification/spec.md#requirement-recovery-through-server-recreation), [recovery after host compromise](../../specs/recovery-and-verification/spec.md#requirement-recovery-after-host-compromise), [safe rollout](../../specs/recovery-and-verification/spec.md#requirement-safe-rollout-within-authorized-scope)).
