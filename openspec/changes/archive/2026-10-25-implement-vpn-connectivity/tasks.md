# Tasks

## 1. Границы и серверная основа

- [x] 1.1 После `implement-ubuntu-platform` и `implement-ubuntu-secrets-administration` сверить выбранные pinned Ubuntu packages и официальный OpenVPN manual; зафиксировать поддерживаемые cipher/auth, compression, control-channel protection и acceleration для TCP/443 без переноса исторических installer-настроек. Проверка: ссылка на использованную upstream-документацию и план измерения throughput/CPU для 1 vCPU добавлены рядом с конфигурацией. Требование: [VPN transports](../../../specs/vpn-connectivity/spec.md#requirement-vpn-transports), [OpenVPN performance priority](../../../specs/vpn-connectivity/spec.md#requirement-openvpn-performance-priority).
- [x] 1.2 Создать Ansible-роли/параметры для IP-конечных точек OpenVPN TCP/443 и WireGuard UDP/443, получающие только server private keys из защищённых SOPS/age runtime-файлов. Проверка: проверка artifacts/output/diffs подтверждает отсутствие plaintext secrets и protocol-compatible test peers завершают handshake на обоих listener. Требование: [VPN transports](../../../specs/vpn-connectivity/spec.md#requirement-vpn-transports), [Encrypted server VPN keys in Git](../../../specs/recovery-and-verification/spec.md#requirement-encrypted-server-vpn-keys-in-git).
- [x] 1.3 Задокументировать и реализовать серверный consumer root-only `/var/lib/bastion/vpn`: отдельные WireGuard public key/address и OpenVPN CA/certificate/CRL/public metadata inputs, атомарное чтение завершённого состояния и server-side apply/verify hooks. Проверка: проверка playbook/templates и fixture подтверждает, что нет static membership list в Ansible inventory/templates, CA private key и client private keys отсутствуют на VPS. Требование: [Local credential issuance and public server state](../../../specs/device-lifecycle/spec.md#requirement-local-credential-issuance-and-public-server-state), [Authenticated and consistent mutations](../../../specs/device-lifecycle/spec.md#requirement-authenticated-and-consistent-mutations).

## 2. Сетевая связность и изоляция

- [x] 2.1 Настроить непересекающиеся IPv4/IPv6 tunnel pools, kernel forwarding и egress/NAT либо эквивалентную маршрутизацию для обоих протоколов через фактические публичные интерфейсы VPS. Проверка: Ubuntu VM test peer передаёт IPv4 и IPv6 трафик через каждый туннель, а controlled dual-stack peer использует IPv6 и сохраняет IPv4 fallback. Требование: [Server-side full-tunnel support and DNS settings](../../../specs/vpn-connectivity/spec.md#requirement-server-side-full-tunnel-support-and-dns-settings), [Prefer IPv6 for outbound connections](../../../specs/vpn-connectivity/spec.md#requirement-prefer-ipv6-for-outbound-connections).
- [x] 2.2 Добавить firewall для IPv4 и IPv6: разрешить только SSH, TCP/443 OpenVPN, UDP/443 WireGuard, established/related и требуемый control traffic; не вводить egress denylist, destination/port restrictions или private/metadata исключения. Проверка: Ubuntu VM test проверяет разрешённые listener, отклонение иных новых входящих соединений и успешный неограниченный tunnel egress к test destinations. Требование: [Inbound services and unrestricted outbound traffic](../../../specs/vpn-connectivity/spec.md#requirement-inbound-services-and-unrestricted-outbound-traffic), [Public key-only SSH](../../../specs/server-administration/spec.md#requirement-public-key-only-ssh).
- [x] 2.3 Добавить правила forwarding, которые до разрешения tunnel→internet блокируют IPv4 и IPv6 между WireGuard peers, между OpenVPN peers и между протоколами, включая устройства одного владельца. Проверка: Ubuntu VM test выполняет матрицу WG↔WG, OpenVPN↔OpenVPN и WG↔OpenVPN для обеих IP-семей и фиксирует отказ каждой межклиентской попытки при доступном внешнем egress. Требование: [Server-side client isolation](../../../specs/vpn-connectivity/spec.md#requirement-server-side-client-isolation).
- [x] 2.4 Рекламировать full-tunnel routes и DNS `1.1.1.1`, затем `8.8.8.8` в применимых OpenVPN/WireGuard settings, не добавляя DNS service/forwarder. Проверка: configuration test проверяет порядок advertised settings и отсутствие локального DNS-процесса, а Ubuntu VM fixture подтверждает пересылку DNS-пакетов через оба туннеля; проверка обоих публичных резолверов внесена в checklist change 6. Требование: [Server-side full-tunnel support and DNS settings](../../../specs/vpn-connectivity/spec.md#requirement-server-side-full-tunnel-support-and-dns-settings).

## 3. Серверные fixtures и регрессии

- [x] 3.1 Добавить test-only public fixtures в контракт `/var/lib/bastion/vpn`, не реализуя management CLI, выдачу или экспорт. Проверка: server-side fixture содержит только допустимые public enrollment data; synthetic test private material остаётся только у test peers и не попадает на VPS, в `/var/lib/bastion/vpn` или Make targets. Требование: [User-owned applications and device configuration](../../../specs/vpn-connectivity/spec.md#requirement-user-owned-applications-and-device-configuration), [Local credential issuance and public server state](../../../specs/device-lifecycle/spec.md#requirement-local-credential-issuance-and-public-server-state).
- [x] 3.2 Проверить server-side consumer public-state contract независимо от lifecycle: fixture атомарно заменяет полное состояние и вызывает apply/verify hook, а неполное или недопустимое состояние отклоняется без сообщения об успехе. Проверка: Ubuntu VM integration test показывает применение полной fixture и отказ неполной/недопустимой fixture; VPN-конфигурация не содержит второго membership state. Требование: [Authenticated and consistent mutations](../../../specs/device-lifecycle/spec.md#requirement-authenticated-and-consistent-mutations), [Revocations survive system lifecycle operations](../../../specs/device-lifecycle/spec.md#requirement-revocations-survive-system-lifecycle-operations).
- [x] 3.3 Добавить проверки OpenVPN server verification inputs: CA/certificates/CRL из public runtime state читаются сервисом, а непригодный CRL не становится основанием заявить readiness. Проверка: сфокусированный Ubuntu VM test покрывает читаемый и missing/unreadable/invalid/expired CRL, а integration report явно фиксирует наблюдаемое admission behavior. Требование: [Effective OpenVPN revocation](../../../specs/device-lifecycle/spec.md#requirement-effective-openvpn-revocation).
- [x] 3.4 Запустить formatter/static checks, `ansible-playbook --syntax-check`, `ansible-lint`, initial/repeated apply и все добавленные Ubuntu VM tests; записать результаты, исключения и отсутствие выполненных live checks. Проверка: команды завершаются успешно либо failure/unrun status документирован без заявления о готовности. Требование: [Automation and integration verification](../../../specs/recovery-and-verification/spec.md#requirement-automation-and-integration-verification).

## 4. Передача live-приёмки

- [x] 4.1 Подготовить для `implement-recovery-and-updates` live-checklist: измерение OpenVPN throughput/CPU на 1 vCPU, protocol-compatible peers для обоих endpoint, IPv4/IPv6 forwarding, controlled IPv6 preference и IPv4 fallback, DNS reachability к `1.1.1.1` и `8.8.8.8`, peer isolation. Проверка: checklist перечисляет команды, ожидаемые evidence и ограничение, что VPS не выбирает адресное семейство за приложения клиентов; до change 6 live-команды не запускаются. Требование: [OpenVPN performance priority](../../../specs/vpn-connectivity/spec.md#requirement-openvpn-performance-priority), [Server connectivity and live-operation verification](../../../specs/recovery-and-verification/spec.md#requirement-server-connectivity-and-live-operation-verification).
- [x] 4.2 Передать в `implement-recovery-and-updates` rollout checklist: сохранить действующую `admin` SSH-сессию, выполнить fresh SSH и оба VPN check после активации, при потере доступа следовать policy server recreation. Проверка: checklist явно относит выполнение к change 6 после foundations и не содержит заявления о выполненном rollout. Требование: [Safe rollout within authorized scope](../../../specs/recovery-and-verification/spec.md#requirement-safe-rollout-within-authorized-scope).

## 5. Исправления по ревью от 2026-10-24

Задачи 5.1–5.6 соответствуют шести замечаниям ревью текущей реализации в том же
порядке. Они уточняют существующие задачи этого change и не меняют нормативные
требования.

- [x] 5.1 **P1 — прекращать доступ WireGuard при остановке сервиса применения и отказе расшифровки секретов.** Unit должен выполнить non-reentrant cleanup при explicit stop и при неуспешном start до `ExecStart`, удалить `wg-bastion` и active links, не останавливая сам себя рекурсивно. Проверка: после установленного рабочего VPN-соединения остановить сервис применения и убедиться в отсутствии доступа; затем проверить отказ перезапуска при нерасшифровываемых секретах и последующее recovery. Требование: [Server-side full-tunnel support and DNS settings](../../../specs/vpn-connectivity/spec.md#requirement-server-side-full-tunnel-support-and-dns-settings), [Authenticated and consistent mutations](../../../specs/device-lifecycle/spec.md#requirement-authenticated-and-consistent-mutations).

- [x] 5.2 **P1 — сделать нарушение изоляции причиной отказа теста.** Peer matrix обязана завершаться nonzero, если любая запрещённая same-protocol или cross-protocol IPv4/IPv6 попытка межклиентской связности успешна; нельзя использовать инверсию exit status, превращающую такое нарушение в PASS. Проверка: regression self-check доказывает failure при разрешённом ping, а matrix проверяет и фиксирует отказ для WG↔WG, OpenVPN↔OpenVPN и обоих направлений WG↔OpenVPN. Требование: [Server-side client isolation](../../../specs/vpn-connectivity/spec.md#requirement-server-side-client-isolation).

- [x] 5.3 **P2 — применять изменённую конфигурацию к работающему OpenVPN.** Изменение server template должно валидироваться и вызывать restart OpenVPN через notification/handler; неуспешная validation не должна restart-ить сервис. Проверка: VM меняет допустимый параметр, подтверждает изменение process timestamp/effective service state, затем unchanged apply не меняет timestamp. Требование: [Automation and integration verification](../../../specs/recovery-and-verification/spec.md#requirement-automation-and-integration-verification).

- [x] 5.4 **P2 — исправить формирование и проверку synthetic DNS-ответов.** Synthetic responder обязан строить RFC 1035 12-byte header и сохранять query ID/question; проверка обязана контролировать QR, RCODE, counts, длину и question, чтобы malformed или ошибочный ответ не дал ложный PASS. Проверка: local self-check и оба tunnel paths принимают только семантически корректный synthetic DNS answer. Требование: [Server-side full-tunnel support and DNS settings](../../../specs/vpn-connectivity/spec.md#requirement-server-side-full-tunnel-support-and-dns-settings).

- [x] 5.5 **P2 — указать тип интерфейса тестовых OpenVPN-клиентов.** Профили с произвольными именами `dev` должны явно задавать `dev-type tun`, совместимый с OpenVPN 2.6. Проверка: generated profiles проходят конфигурационную проверку и оба OpenVPN peer tunnel устанавливаются в matrix. Требование: [VPN transports](../../../specs/vpn-connectivity/spec.md#requirement-vpn-transports).

- [x] 5.6 **P2 — согласовать финальный VM-сценарий с восстановленным состоянием и проверить идемпотентность.** После negative check missing `current` harness обязан восстановить полный valid state до финального apply; финальный сценарий не должен ожидать absence уже восстановленного состояния. Проверка: полный unchanged apply после recovery даёт `changed=0 failed=0`, а VPN-only reapply не меняет timestamp сервиса. Требование: [Automation and integration verification](../../../specs/recovery-and-verification/spec.md#requirement-automation-and-integration-verification).

## Фактические staged evidence (2026-10-24)

Сверка 1.1: [версии, параметры и план измерений](../../../../docs/vpn-connectivity.md#package-and-openvpn-parameter-review-2026-10-24)
проверены по Ubuntu security/package metadata, manual OpenVPN 2.7 и upstream
`README.dco.md` тега v2.7.0. Обнаружено, что упомянутых в задаче APT pins в
реализации нет: сохранён нормативный порядок `state: present` и явного ручного
maintenance, а версии записаны как датированный снимок источников, не как
установленные пакеты. Исправлена ссылка на manual 2.6; план измерений передан
в checklist change 6. VPN static test и strict OpenSpec validation успешны.
Измерения производительности и применение обновлений в рамках 1.1 не выполнялись.

Историческое состояние до последующего focused retry 5.1: статические проверки,
syntax, ansible-lint и отдельные QEMU-сценарии были успешны;
две последовательные точные canonical matrix run завершились
`VPN_VM_PEER_MATRIX_PASS`. Это не один непрерывный итоговый harness: lifecycle,
изменение конфигурации, идемпотентность и peer matrix выполнялись отдельными
сценариями на synthetic fixture. В тот момент 3.4 и 5.1 ещё были открыты,
хотя частичные проверки stop/secrets recovery были успешны. Последующий
role-backed retry и актуальный статус 5.1 записаны в
`docs/vpn-connectivity.md`; незапущенные live/capability проверки там же.

После этих исправлений были выполнены проверки 3.4 и записаны фактические
результаты; 5.1 закрыта отдельным focused retry.
Закрытие 5.1–5.6 не заменяет остальные критерии разделов 1–4: в частности,
проверки входящего firewall и всех CRL-сценариев.
Live-проверки остаются в change 6 и требуют отдельной авторизации.

Задача 2.1: controlled IPv6-first TCP и IPv4 fallback после IPv6 refusal
подтверждены через WireGuard и OpenVPN в исправленной canonical peer matrix:
`VPN_VM_PEER_MATRIX_PASS`, exit 0. Responder проверяет source address VPS после
NAT для обеих семей. Роль уже содержала нужные pools/sysctl/masquerade;
добавлены тесты и исправлен формат ответа тестового responder. Проверка
выполнена на сохранённых Ubuntu VM после восстановления временной тестовой
сети; это staged evidence, а не новый полный непрерывный harness PASS.
[Детали и ограничения](../../../../docs/vpn-connectivity.md#task-21-controlled-dual-stack-egress-2026-10-24).
