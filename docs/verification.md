# Evidence Ubuntu foundation

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
DNS/Internet пробы и `maintenance`/обновление пакетов. VPN, device lifecycle,
notifications и recovery остаются отдельными незавершёнными этапами.

## Contracts for following changes

- `implement-ubuntu-secrets-administration` создаёт и проверяет `admin`; только
  затем routine `site`/maintenance использует SSH как `admin` + password prompt
  for `su`. Bootstrap provider account не является routine path.
- `implement-vpn-connectivity` добавляет VPN/firewall/forwarding; foundation не
  открывает порты и не меняет provider API или disk layout.
- `implement-device-lifecycle` владеет issuance/revocation и CA/client secrets.
- `implement-ssh-notifications` может читать native `/var/log/auth.log`; его
  retention уже задаётся logrotate на 30 дней, но его integration ещё не создана.
