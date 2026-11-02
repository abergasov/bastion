# Локальный жизненный цикл VPN-устройств

> Historical note: remaining age/SOPS/recipient wording records superseded test
> evidence only. Current operations use controller-only Ansible Vault.

`make vpn-add-wg` и `make vpn-add-open` запускают единственный локальный
authority manager. Current implementation stores its Git copy as controller-only
Ansible Vault ciphertext `secrets/vpn-authority.yaml`; `vault_password_file`
from ignored input remains on the controller. The VPS receives neither Vault
password nor owner authority. The historical age/SOPS operational evidence below
is superseded and is not a current invocation contract.

It stores decrypted state in the owner-only directory
`${XDG_STATE_HOME:-~/.local/state}/bastion/vpn` (0700). Its only
Git copy is `secrets/vpn-authority.yaml` (0600), encrypted with controller Vault.
The legacy statements about encryption only for
`owner_age_recipient` from ignored `inventory/secrets-input.json` are historical.
Переменная `BASTION_OWNER_AGE_IDENTITY` должна указывать на owner identity
0600 вне репозитория. VPS recipient намеренно не принимается для этого файла.
Профили хранятся в том же local state каталоге с mode 0600 и не попадают в Git.

## Операции

Все команды используют `VPN_HOST`; `CLIENT` нужен только для add/export:

```sh
make vpn-add-wg VPN_HOST=vpn.example CLIENT=phone
make vpn-add-open VPN_HOST=vpn.example CLIENT=laptop
make vpn-list-wg VPN_HOST=vpn.example
make vpn-list-open VPN_HOST=vpn.example
make vpn-export-wg VPN_HOST=vpn.example CLIENT=phone
make vpn-export-open VPN_HOST=vpn.example CLIENT=laptop
make vpn-revoke-wg VPN_HOST=vpn.example
make vpn-revoke-open VPN_HOST=vpn.example
make vpn-renew-open VPN_HOST=vpn.example
```

Revoke показывает локальный список и принимает только точное каноническое имя.
Пустой ввод, EOF, отмена либо неизвестное имя завершаются до изменения state.
Имена, endpoint, WireGuard public keys, pools и дубликаты проверяются до
создания ключа, записи age ciphertext или SSH. Повторная выдача не заменяет
существующий private key.

## Продление OpenVPN CRL

По [исправленной спецификации](../openspec/specs/device-lifecycle/spec.md)
CRL автоматически проверяется VPS ежедневно и renews за семь дней до истечения;
пропущенный запуск догоняется systemd timer. Service подписывает 30-дневный CRL
из immutable public release (`ca.crt`, `index.txt`, membership revision),
сохраняет новый immutable release и sequence вне controller authority. Равная
revision публикации не может заменить более новый server CRL; старая revision
отклоняется. Вне окна renewal ничего не меняется и WireGuard не
перенастраивается.

CA key находится только в root-owned runtime projection VPS и не доступен
OpenVPN. Отсутствующий, не mode-0600, не root-owned или не соответствующий CA
ключ даёт reported failure; истёкший/невалидный CRL не допускает запуск listener.
Проверяйте `crl-status.json` и systemd journal. `make vpn-renew-open` — ручной
VPS-side diagnosis/recovery path через `admin` + interactive `su`, не controller
signing и не передача CA key.

`recover-fresh` — не обычная lifecycle-операция и не способ повторить publish
текущей authority. Он применяется только после решения, что current local
revocations недоступны: создаёт пустую fresh authority и требует явного
re-enrollment. Команда не читает и не публикует существующий `vpn-authority.yaml`
(включая Git restore); её повтор возможен только для локального, привязанного к
хэшу pending fresh transition после `make apply`. Она требует protected
replacement JSON (0600) и создаёт complete fresh `server.yaml` вместе с
`vpn-server.yaml`, не читая старый server ciphertext. Обычные `add`/`revoke`/export
сохраняют существующую authority и для такого восстановления не подходят.

После проекции CA на VPS `recover-compromised` намеренно отказывается от
CA-preserving recovery и направляет к `recover-fresh`. Подтверждённая compromise
требует fresh CA trust, fresh server/device credentials, replacement profiles и
явного повторного enrollment каждого разрешённого устройства; старые profiles
нельзя считать безопасными. Current-authority marker не ослабляет это правило.

Для `replace-server` и `recover-fresh` после atomарного local save и записи Vault ciphertext
сначала пытаются stage соответствующую public release, но всегда возвращают
`partial failure`. Staging может не дойти до VPS или намеренно fail-closed, пока
runtime использует прежний key; это не объявляется успехом. Только после
`make apply` идентичный retry проверяет publish/apply и удаляет pending state.
Для fresh оба новых Vault ciphertext сначала полностью записываются во
временные mode-0600 файлы до замены любого target. Сбой до replace сохраняет оба
прежних ciphertext; между двумя атомарными replace возможен только явный
cross-file partial, который тот же retry записывает заново.

Экспорт WireGuard содержит `AllowedIPs = 0.0.0.0/0, ::/0` и DNS в порядке
`1.1.1.1`, `8.8.8.8`. OpenVPN export содержит те же маршруты/DNS и ровно один
`peer-fingerprint` SHA-256 от current local server certificate. Отсутствующий
сертификат или private key прекращает export без файла. Удаление профиля не
является revoke.

Focused real-age regression не зависит от временного каталога VM: он ищет
исполняемые `age` и `age-keygen` через `BASTION_AGE_BIN` и
`BASTION_AGE_KEYGEN`, затем через `PATH`. Если ни один способ не доступен, тест
останавливается с явной setup error; для отдельного запуска укажите, например,
`BASTION_AGE_BIN=/abs/path/age BASTION_AGE_KEYGEN=/abs/path/age-keygen \
python3 tests/device-lifecycle-test.py`.

## PKI, server keys и публикация

Manager использует `wg genkey`/`wg pubkey` для пары WireGuard и OpenSSL
`ca -revoke`/`ca -gencrl` для CRL. При первой выдаче он сам создаёт
`secrets/vpn-server.yaml`: отдельный Vault ciphertext с OpenVPN CA key и двумя
server private keys. Это единственное разрешённое исключение для CA: client
private keys, полная authority и Vault password туда не переносятся. Следующий стандартный `make apply`
доставляет этот ciphertext, после чего повтор той же lifecycle-команды
публикует release; до этого команда возвращает `partial failure`.
Runtime paths остаются
`/run/secrets/bastion/openvpn-ca-key`, `/run/secrets/bastion/openvpn-server-key` и
`/run/secrets/bastion/wireguard-server-key`. Server verifier сравнивает public
key certificate с OpenVPN runtime private key до activation.

Явная смена server identity выполняется owner-side командой
`python3 scripts/bastion-vpn-lifecycle replace-server --vpn-host "$VPN_HOST"`.
Она сохраняет CA, clients и CRL/revocations, выпускает новые OpenVPN/WireGuard
server keys, создаёт replacement SOPS ciphertext, пытается stage release и затем
возвращает partial failure до `make apply` и retry. Новые OpenVPN exports получают
fingerprint только replacement cert.

После atomарного owner-only age save manager создаёт public-only tar release,
передаёт его по SCP с `inventory/known_hosts` и `StrictHostKeyChecking=yes`, а
затем входит по SSH как `admin` с TTY и выполняет интерактивный `su`. Root-only
publisher принимает только ожидаемый архив, создаёт immutable release,
атомарно меняет `current` и вызывает существующий verify/apply hook. Archive
содержит только текущую release schema: CA/server cert/CRL/metadata и WG
public peers. Сбой после ciphertext — `partial failure`; authority сохранена,
но success не заявляется.

## Проверенные источники (2026-10-25)

- [OpenSSL `ca`](https://docs.openssl.org/master/man1/openssl-ca/) документирует
  CA database, `-revoke` и CRL options; state поэтому сохраняет index/serial/CRL
  number вместе с CA.
- [WireGuard Quick Start](https://www.wireguard.com/quickstart/) документирует
  `wg genkey` и `wg pubkey`; [wg(8)](https://man7.org/linux/man-pages/man8/wg.8.html)
  документирует runtime peer removal через `wg set ... peer ... remove`.

Это local/synthetic implementation evidence, не разрешение на deployment и не
доказательство live VPS или пользовательского VPN клиента.

## Фактическая VM-проверка (2026-10-25)

В сохранённой disposable Ubuntu 26.04.1 fixture (20 GiB overlay) manager с
синтетическими age/SOPS/OpenSSL/WireGuard ключами выполнил strict-host-key
publish через `admin` и интерактивный `su`, затем `add`, `list`, `export` и
`revoke` обоих protocol и проверку public-only release tree.

Отдельный resumed active-transition прогон выпустил свежие synthetic devices,
подтвердил действующий WireGuard handshake/data path и OpenVPN A+B sessions,
а затем отозвал их через тот же manager. Он подтвердил немедленный отказ
трафика существующего и нового WireGuard peer, server-induced teardown
активной OpenVPN A session, fresh A denial и reconnect non-revoked B. После
reboot и успешного Ansible reapply (`ok=37`, `failed=0`) те же revoked denial и
survivor reconnect снова прошли; итоговый marker —
`DEVICE_LIFECYCLE_RESUME_PASS` с exit 0. Это segmented synthetic fixture
evidence, не проверка live VPS или пользовательского production-клиента.

Production revoke допускает единственное устройство и не передаёт client
material на VPS. Его success требует published CRL, restart/readiness OpenVPN и
verified persistent/live public server state. Controlled VM fixture отдельно
доказывает revoked denial, active-session termination и reconnect non-revoked
client; это integration evidence, а не runtime management hook.
