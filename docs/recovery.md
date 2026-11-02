# Восстановление после потери VPS или административного доступа

> Historical note: remaining age/SOPS/recipient wording below is superseded
> evidence. Current recovery uses controller-only Ansible Vault.

CA private key остаётся только на controller; обычная compromise VPS не делает
CA скомпрометированным. Она требует recreation и ротации host-accessible
secrets. Новый CA, новые server/device credentials и явный enrollment нужны
только при доказанном предыдущем CA-key projection на этот VPS; тогда старые CA
trust, certificates и profiles не переносятся в новую trust domain.

Это операторская процедура обычной замены VPS без подтверждённой компрометации.
Она дополняет выполненные lifecycle-задачи 2.1–2.4
[плана recovery](../openspec/changes/implement-recovery-and-updates/tasks.md).
Описанные ниже local lifecycle-переходы не являются разрешением на deployment:
для объявления готовности всё ещё требуется отдельное cross-component evidence
раздела 4 и отдельно авторизованные live-проверки.
Создание, изменение или удаление live VPS требует отдельной авторизации.

## 1. Определить причину и доступное локальное состояние

При обычной потере сервера или административного доступа восстанавливайте сервис
на новом VPS через существующую [установку Ubuntu](installation.md). Console/rescue
доступ к прежнему серверу и его аварийный root-пароль не нужны. Старый VPN server
key также не является обязательным входом; сохранение прежних подключений
не гарантируется.

При подтверждённой compromise VPS сначала установите, был ли CA когда-либо
спроецирован на этот VPS. Без такого exposure сохраните controller CA, но
пересоздайте VPS и ротируйте host secrets. При подтверждённом старом exposure
подготовьте mode-0600 replacement JSON и запустите `recover-fresh` с
отсутствующим authority ciphertext: fresh path создаёт новый CA и complete Vault
ciphertext `server.yaml` и `vpn-server.yaml` без CA projection; затем каждый
authorised device получает новую credential и profile через явный enrollment.
Current-authority marker защищает обычные операции от stale ciphertext, но не
делает ранее раскрытый CA безопасным.

На доверенном компьютере проверьте наличие controller Vault password source и актуальных локальных
CA/client keys, записей выдачи и отзывов. GitHub содержит только committed и
pushed ciphertext; старая копия или версия конфигурации не доказывает актуальность
отзывов. Перед публикацией состояния сверьте его с текущими authoritative records
по [контракту lifecycle](../openspec/specs/device-lifecycle/spec.md#requirement-revocations-survive-system-lifecycle-operations).
Без актуальных записей не запускайте обычные lifecycle-операции над найденным
ciphertext. На доверенном компьютере запустите
`python3 scripts/bastion-vpn-lifecycle recover-fresh --vpn-host "$VPN_HOST" \
--replacement-secrets-file /protected/replacement.json`
только с отсутствующим `secrets/vpn-authority.yaml` (либо явно указанным
отсутствующим `--state-file`). Команда намеренно отказывается от любого уже
существующего ciphertext, включая восстановленный из Git, до расшифровки или
публикации. Она выпускает пустую fresh authority, сохраняет её только в
owner-only Vault ciphertext и создаёт complete fresh Vault ciphertext в `server.yaml`
и `vpn-server.yaml` for controller delivery only. До `make apply` она
пытается stage пустой public state и всегда возвращает partial failure: transport
либо проверка старого runtime key могут остановить stage. Затем выполните
`make apply` и повторите ту же команду с теми же `--workdir`/`--state-file`:
retry проверяет publication и снимает pending. После
этого явно заново зачислите каждое разрешённое устройство обычными `vpn-add-*`;
старые credentials не должны получить доступ. Команда не удаляет и не
восстанавливает старый ciphertext, не создаёт backup и не выполняет push.
При потере Vault password вместе с расшифрованным состоянием нужны новые
authority и credentials: оставшийся ciphertext их не восстановит.

## 2. Подготовить новый VPS и зашифрованные входы

После авторизации вручную создайте VPS по [installation.md](installation.md):
Ubuntu Server, публичные IPv4/IPv6 и публичный SSH-ключ владельца. Подготовьте
локальный inventory для новых адресов. Получите и сверьте новый Ed25519 host key
через доверенный канал провайдера, затем запишите его для нового `ansible_host`
в `inventory/known_hosts`. Повторное использование IP не делает прежний host key
правильным. При невозможности проверить новый ключ остановитесь; не отключайте
проверку SSH identity. Проверьте bootstrap-доступ с root либо non-interactive
sudo согласно installation workflow. Доступ к консоли старого VPS не требуется.

Подготовьте входы по [контракту секретов](secrets-and-administration.md):

- Проверенный новый SSH host key в `inventory/known_hosts`; owner SSH private key
  остаётся вне VPS.
- Новый OpenVPN server key/certificate и replacement profiles; новый CA нужен
  только после подтверждённого прежнего CA exposure. Vault ciphertext хранит
  только server keys для delivery, а Vault password и CA остаются на controller.

Client private keys, CA и authoritative records остаются локально в owner-only
Vault ciphertext. На VPS публикуются только public membership data, signed CRL
и server private keys в защищённых runtime files.
Не помещайте plaintext, профили или private keys
в inventory, Git, логи или аргументы команд. Не восстанавливайте membership из
старого playbook или ciphertext без сверки отзывов до открытия VPN listeners.

## 3. Повторить установку и проверить результат

Когда зависимости процедуры готовы и live-работа разрешена, выполните существующий
`make bootstrap`, затем `make apply` по installation workflow. Это настройка уже
установленной Ubuntu без форматирования дисков. Сохраните рабочую bootstrap-сессию
до проверки свежего SSH-входа как `admin`; дальнейшие привилегированные операции
используют `admin` и интерактивный `su`. Заданные владельцем пароли `admin`/`root`
поступают через SOPS; отказ от аварийного root-пароля не отменяет их настройку.

Через lifecycle workflow опубликуйте проверенное актуальное public state и
выпустите replacement profiles на доверенном компьютере. Они используют новый
endpoint; OpenVPN содержит только SHA-256 fingerprint нового локально выпущенного
сертификата в `peer-fingerprint`. Передайте владельцу устройства
[инструкцию замены профиля](profile-replacement.md). Импорт и изменение доверия
в приложении не происходят автоматически и не требуют обязательной проверки
каждого устройства для приёмки сервера.

Перед объявлением готовности сохраните отдельные результаты обязательных
[recovery/integration и live-проверок](../openspec/changes/implement-recovery-and-updates/tasks.md)
(разделы 4 и 5.1): fresh SSH, оба VPN, forwarding/DNS/isolation, соответствие
профилей новой identity и отказ отозванным credentials, а также остальные
эксплуатационные проверки. Успешный Ansible run их не заменяет. При ошибке
зафиксируйте выполненные шаги, частичные изменения и непроверенные состояния;
не объявляйте recovery успешным и не обходите проверки старым membership или pin.

Основание: [recovery through recreation](../openspec/specs/recovery-and-verification/spec.md#requirement-recovery-through-server-recreation).
Для этой процедуры не создавался VPS и не выпускались или не копировались
production secrets. Synthetic component/VM evidence не является разрешением на
deployment и не заменяет remaining cross-component или live-проверки.
