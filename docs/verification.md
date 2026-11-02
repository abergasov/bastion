# Evidence Ubuntu foundation

## Current verification scope

Этапы 1–5 и переход на UFW завершены по локальным планам. Автономное продление
CRL реализовано и имеет synthetic regression coverage, но его disposable-VM
проверки и итоговая совместная проверка остаются открытыми:
[fix-review-findings, 1.6 и 2.1](../openspec/changes/fix-review-findings/tasks.md).
Результаты ниже относятся к указанным версиям и сценариям; они не закрывают
эти задачи или [live readiness, 5.1](../openspec/changes/implement-recovery-and-updates/tasks.md).

## UFW status

Текущая UFW-проверка выполняется только на disposable Ubuntu 26.04 QEMU с
синтетическими ключами и секретами, без VPS и Telegram. Уже сохранены staged
markers: normal apply и fresh-SSH reboot, post-reboot runtime gate (raw
dual-stack chains/NAT/fail2ban action), IPv4/IPv6 fail2ban baseline → ban →
deny → unban, unchanged reapply `ok=77 changed=0`, ingress/peer matrix и
WireGuard lifecycle recovery; missing-current state корректно дал ожидаемый
отказ и затем был восстановлен. Текущие логи находятся в защищённом
`/tmp/bastion-vpn-vm.CHxKSV/` и не являются долговечным артефактом.

После UFW reload отдельный seeded established/related сценарий также прошёл:
восемь IPv4/IPv6 same/cross-tunnel TCP flows сначала обменялись данными через
временные точные test-only allow rules, затем эти rules были проверенно удалены
и established traffic был заблокирован до return allowance. Fresh clean VM suite
и distinct cross-component recovery suite завершились успешно. Исторические
nftables-результаты ниже не подтверждают UFW. В synthetic socket transport
IPv6 NDP потребовал test-only static neighbours; это ограничение стенда, а не
изменение production policy и не доказательство provider IPv6.

После clean VPN gate recovery был проверен отдельным existing cross-component
VM suite. Aggregate `recovery-integration-test` намеренно не запускался: он
повторяет тот же full VPN VM suite; выбранный suite отдельно проверил recovery
ролей firewall/VPN/secrets/notifications, idempotent reapply и reboot.
`/tmp/bastion-recovery-cross-final.log` зафиксировал initial `ok=116 changed=63`,
repeat `ok=109 changed=0`, reboot 103 s и
`RECOVERY_CROSS_COMPONENT_VM_PASS`. Это также disposable synthetic evidence.

Поздний targeted continuation завершился `RESUME_AFTER_INGRESS_LIVE_PASS`:
revoked OpenVPN A был denied при активном/reconnected B, reboot занял 98 s,
а reapply дал `ok=77 changed=1` только из-за fixture-state copy; denial A
сохранился после reboot. Это reuse защищённого synthetic fixture, не замена
обязательному fresh clean VM run.

Fresh clean VM suite `/tmp/bastion-vpn-vm.Y1k727/` завершился terminal marker в
`/tmp/bastion-vpn-clean-final.log`. Он подтвердил четыре pre-migration safety
gate (invalid interface, stale UFW `changed=0`, injected enable code 42 и fresh
no-mux SSH failure) с сохранением legacy policy, normal migration, unchanged
reapply `ok=77 changed=0`, WireGuard lifecycle (stop/failed-start cleanup,
denied/available traffic и recovery), firewall ingress/peer matrix, UFW reload,
true seeded isolation восьми flows и revoke/reboot/reapply tail. В tail reapply
дал `ok=77 changed=1` только из-за fixture-state copy; revoked A остался denied,
а B active/reconnected. Это local synthetic evidence, не live-VPS evidence.

> Historical note: SOPS/age evidence below predates the Vault migration and is
> not current Ubuntu/Ansible Vault verification.

Проверки выполнены локально без VPS и без мутаций удалённого хоста:

- `make test`: synthetic SSH preflight отвергает некорректный prefix, чужой
  Ed25519 host key, не-Ubuntu 26.04 и bootstrap account без root/sudo до любого
  provision marker; static contract не допускает Nix/disko runtime path.
- Временный `/tmp` venv с `ansible-core 2.21.5`: syntax-check трёх playbook и
  `ansible-lint` production profile прошли.
- `pip download --no-deps --require-hashes -r requirements-artifact.txt`
  проверил официальный 2.21.5 wheel.

Изолированный QEMU 11.1.2 fixture использовал TCG (KVM отсутствует), 1 vCPU,
2,057,093,120 B RAM, 20 GB qcow2 overlay и Ubuntu 26.04.1 cloud image. Его
официальный SHA-256 `5645d0318ad21f643ebb1ac4567514620e9893380b07b0201fda163baa5b7eb5`
совпал с published checksum. Initial bootstrap завершился `ok=14 changed=11`,
повторный bootstrap и routine `admin` + `su` apply — без changes. Fixture
заменил generated `50-cloud-init.yaml` только после записи полного Bastion
Netplan и disable-file для future cloud-init network configuration.

После reboot `networkctl` показал `routable/online`; статические IPv4/IPv6
адреса, default routes и DNS сохранились, оба QEMU gateway отвечали на ping,
а archive.ubuntu.com разрешался и был доступен по HTTP. Persistent journal
имеет `root:systemd-journal 2755 /var/log/journal`, `MaxRetentionSec=30day`;
native global `logrotate -f /etc/logrotate.conf` успешно обработал rsyslog,
после чего auth log продолжил получать записи. Оба apt timer отключены.

Explicit maintenance выполнил реальный `apt dist-upgrade`, записал версии в
`/var/lib/bastion/package-versions.txt` (root:root 0600), а повторный
maintenance с facts и post-maintenance role reapply завершился без changes.
Отдельно проверенный apt/DNS failure вызвал rescue с recovery message и всё
равно записал versions record.

Не выполнены: VPN throughput, VPN services/firewall/forwarding, real public
provider addressing and any live deployment. Swap в fixture отсутствовал;
после package update root filesystem использовал около 13% (2,433,892,352 B
из 19,594,608,640 B). Эти ограничения и live network/VPN throughput переданы
в финальный checklist change `implement-recovery-and-updates`.

## Secrets regression verification — 2026-10-23

Повторная проверка выявила два дефекта: отсутствие `/run/secrets` после
загрузки блокировало secrets service и зависимый SSH; проверка получателей
SOPS принимала recipient владельца из комментария вместо `sops.age[]`.
Исправлены создание runtime parent перед дешифрованием и структурная
проверка YAML metadata. Make использует project venv для зависимости PyYAML.

Регрессионные тесты проверяют отсутствующий runtime parent, recipient только
в комментарии или подстроке и некорректные YAML/metadata. `make test`,
Ansible syntax-check, ansible-lint production, strict OpenSpec validation и
`git diff --check` прошли; для Ansible использовались writable temp/cache
каталоги в `/tmp`.

На отдельном QEMU/TCG overlay Ubuntu 26.04.1 с синтетическими секретами
исправленный decryptor автоматически создал runtime parent; secrets service
и SSH стали active. Права каталога 0700 и файлов 0600 проверены. Повреждённый
ciphertext блокировал дешифрование, старый runtime отсутствовал. После
восстановления ciphertext и реальной перезагрузки обе службы снова active,
права корректны. VM выключена; исходный образ не изменён. Локальный протокол:
`/tmp/bastion-qemu-review-yieayh6_/result.json` (временный артефакт).

Этот прогон проверял исправления установленного скрипта и служб, не полный
Ansible provisioning. Live VPS, внешняя сеть и реальные секреты не проверялись.
Этап secrets/administration уже архивирован; активные этапы не закрывались.

## Full current Ansible VM verification — 2026-10-23

На новом disposable QEMU/TCG overlay Ubuntu 26.04.1 текущие `bootstrap.yml` и
`site.yml` выполнены через pinned local Ansible по SSH, доступному только на
`127.0.0.1`. Использовались исключительно синтетические секреты.

| Проверка | Результат |
| --- | --- |
| Первый bootstrap | `ok=36 changed=20 failed=0` |
| Повторный bootstrap | `ok=33 changed=0 failed=0` |
| Первый site через `admin` + `su` | `ok=39 changed=2 failed=0` (final SSH policy) |
| Повторный site | `ok=38 changed=0 failed=0` |
| Admin SSH по ключу после холодной загрузки | Успешно |
| Root / другой пользователь / password / keyboard-interactive SSH | Отказ |
| `su` с верным / неверным паролем | UID 0 / отказ |
| Runtime secrets после загрузки | Каталог 0700, четыре файла 0600, root:root |
| Независимые owner/VPS recipients | Оба decrypt server ciphertext; посторонний ключ — нет |
| Owner-only fixture | Owner decrypt успешен, VPS — отказ |
| Fail2ban IPv4 и IPv6 | Автоматический ban после неудачных входов; верный ключ заблокирован; unban восстанавливает доступ |
| Повреждённый ciphertext | Decryption и запуск SSH отклонены, stale runtime отсутствует |
| Восстановление ciphertext | Secrets и SSH снова active, внешнее admin SSH успешно |

Fresh image имел Universe source, но устаревший APT index: `age` не имел
Candidate до `apt-get update`. Роль исправлена: обновляет index перед
установкой `age`, без общего package upgrade. Локальные `make test`, syntax,
production lint, strict OpenSpec validation и diff-check прошли; правка
проверена review и повторным bootstrap на новом overlay.

Первоначальный fixture неверно задавал `enp0s2` вместо фактического `ens3`.
Доступ сохранялся через `/run/systemd/network/zzzz-dracut-default.network`
(DHCP), поэтому тот прогон сам по себе не доказывает корректность статической
сети. Дополнительный прогон **текущей Ansible platform-роли** с `ens3` и
адресами QEMU завершился `ok=14 changed=2`, повторный — `ok=13 changed=0`.
Подтверждены статические IPv4/IPv6, маршруты, DNS и использование
`/run/systemd/network/10-netplan-ens3.network` вместо DHCP fallback.
После реального reboot статические адреса, маршруты и DNS сохранились;
IPv4/IPv6 шлюзы QEMU ответили на ping, fresh admin SSH прошёл,
secrets service и SSH active. VM выключена.

Временные протоколы в `/tmp/bastion-full-verify-j90q474f/`:
`root-runtime-result.json` (21 успешная runtime-проверка),
`recipient-result.json`, `network-result.json`. Предыдущие неполные протоколы
этого каталога не являются итогом проверки. Исходные backing images не менялись.

Playbooks проверялись напрямую с loopback/private fixture inventory; публичный
адресный контракт `make bootstrap` проверяется отдельными preflight-тестами.
В этом повторном прогоне не выполнялись live VPS/provider проверки, внешние
DNS/Internet пробы и `maintenance`/обновление пакетов. На дату этого прогона
VPN, device lifecycle, notifications и recovery ещё не были завершены;
последующие результаты отражены отдельно ниже и в
[актуальном плане](../openspec/README.md#implementation-plan).

## Recovery integration gate

`make recovery-integration-test` повторно запускает platform/VPN/SSH static
contracts и synthetic lifecycle tests; он не запускается из `make test` и не
объявляет live readiness. Для тяжёлых disposable VM suites используется
явный `BASTION_RECOVERY_VM=1 make recovery-integration-test`. При отсутствии
fixture или real-age tools gate печатает `RECOVERY_SKIP`/`PARTIAL`; ошибка
выбранного suite завершает gate с ошибкой. VM evidence остаётся synthetic и
не включает VPS, reboot/recreation live host, Telegram или реальные secrets.

## Current local recovery verification — 2026-10-31

Все результаты этого раздела относятся только к disposable QEMU/TCG и
синтетическим Vault fixtures. `SSH_NOTIFICATIONS_VM_PASS`
(`/tmp/bastion-ssh-notifications-vm.GnGUuj`) подтвердил initial apply
`ok=57 changed=40 failed=0`, repeated apply `ok=50 changed=0 failed=0`, fresh
notification check и reboot с local mock endpoint. Это не отправляло Telegram.

Cross-component initial role run
`/tmp/bastion-recovery-cross-component.ZYnnCk` потребовал только fixture
directory-mode correction; COW continuation
`/tmp/bastion-cross-final-diagnose.Awz873` прошла repeated apply
`ok=69 changed=0 failed=0`, fresh SSH local mock, reboot четырёх служб
(secrets, WireGuard, OpenVPN, notifications) и boot-notification mock.
Это synthetic continuation, а не live server claim.

`make syntax` прошёл для `bootstrap.yml`, `site.yml` и `maintenance.yml` при
`ANSIBLE_LOCAL_TEMP` и `ANSIBLE_HOME` в `/tmp`; `bash -n` прошёл для VM,
recovery и WireGuard fixture helpers. `ansible-lint 26.10.1`, установленный
локально в `/tmp`, прошёл на затронутом
`roles/administration/tasks/main.yml` (production profile). Полный lint пока
сообщает ровно пять ранее существующих несвязанных findings: yaml indentation
в `.serena/project.yml:88` и `var-naming[no-role-prefix]` в
`roles/secrets_administration/tasks/main.yml:20`, `:33`, `:49` и `:65`.
Они не скрыты и не исправлялись этим recovery work.

Independent lifecycle VM завершилась `DEVICE_LIFECYCLE_VM_PASS`
(`/tmp/bastion-device-lifecycle-vm.HjEosN/verification-result.txt`): initial
apply `ok=44 changed=27 failed=0`, server-replacement `ok=39 changed=3
failed=0`, compromise-recovery `ok=39 changed=5 failed=0`; add/export/revoke,
новый fingerprint, retained revocations, rotated root password и graceful
shutdown прошли.

VPN component initial apply в `/tmp/bastion-vpn-vm.Y0msLO` дал `ok=44
changed=27 failed=0`, repeated apply — `ok=37 changed=0 failed=0`. После
узких fixture fixes retained continuation
`/tmp/bastion-vpn-continuation.yRKOCa` завершилась
`VPN_VM_CONTINUATION_PASS`: protocol-compatible peer matrix и firewall ingress
прошли; revoked OpenVPN A fresh denial при активном B и B reconnect прошли до
reboot, а после actual reboot (67 s) и reapply `ok=37 changed=1 failed=0`
fresh A denial/B active прошли снова. Это документированная continuation после
fixture fixes, не один uninterrupted runner. Live VPS, real Telegram и
пользовательские приложения исключены.

## Contracts for following changes

- `implement-ubuntu-secrets-administration` создаёт и проверяет `admin`; только
  затем routine `site`/maintenance использует SSH как `admin` + password prompt
  for `su`. Bootstrap provider account не является routine path.
- `implement-vpn-connectivity` добавляет VPN/firewall/forwarding; foundation не
  открывает порты и не меняет provider API или disk layout.
- `implement-device-lifecycle` владеет issuance/revocation и CA/client secrets.
- `implement-ssh-notifications` может читать native `/var/log/auth.log`; его
  retention задаётся logrotate на 30 дней. Его synthetic Vault/QEMU integration
  с local mock endpoint прошла; live Telegram delivery не проверялась.
