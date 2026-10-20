# Design

## Context

См. [proposal.md](proposal.md) для мотивации. Репозиторий greenfield: NixOS-конфигурации, management CLI и NixOS-тесты ещё отсутствуют. Baseline [vpn-connectivity](../../specs/vpn-connectivity/spec.md) уже определяет требуемое внешнее поведение; этот change его реализует и потому не содержит delta-спецификаций.

До реализации необходимы результаты `implement-nixos-platform` (flake, хост, адреса, базовая сеть) и `implement-secrets-and-administration` (SOPS/sops-nix и защищённые runtime-файлы серверных ключей). `implement-device-lifecycle` остаётся владельцем выдачи, отзыва и экспорта устройств; его работа не является предварительным условием для создания VPN-конфигурации и test fixtures.

## Goals / Non-Goals

**Goals:**

- Описать минимальную серверную конфигурацию для OpenVPN TCP/443, WireGuard UDP/443, IPv4/IPv6 forwarding, firewall, DNS-рекламы и изоляции пиров.
- Сохранить единственный источник membership state на компьютере администратора и предоставить серверу только public runtime state.
- Сделать проверяемыми туннельный egress, DNS-настройки и изоляцию без реализации пользовательского CLI.

**Non-Goals:**

- Выдача, отзыв, экспорт профилей, локальные CA/client private keys и пользовательский интерфейс управления устройствами.
- DNS-сервер, DNS-forwarder, фильтр исходящих назначений или особый запрет provider/private/metadata сетей.
- Выбор или тестирование приложений и ОС клиентов, kill switch, DNS leak prevention и принуждение клиентов к IPv6.
- Неподтверждённые утверждения о версиях, шифрах, compression, control-channel protection или acceleration до проверки актуальной upstream-документации на этапе реализации.

## Decisions

### Нативные NixOS-сервисы и секреты в runtime

Реализация использует поддерживаемые на выбранной pinned NixOS native modules и пакеты для OpenVPN, WireGuard, сетевой фильтрации и systemd. Приватные ключи серверов берутся только из защищённых SOPS/sops-nix runtime-файлов; CA private key и client private keys не появляются на VPS. Это сохраняет декларативность платформы и границу секретов из `recovery-and-verification`.

Альтернатива — перенос старых интерактивных installer-скриптов или отдельный framework управления VPN — отклоняется: она создаёт второй lifecycle и не нужна для требуемой серверной конфигурации.

### Единая политика forwarding и firewall

Конфигурация включает kernel forwarding для IPv4 и IPv6 и применяет правила к обоим семействам. Политика входа допускает только SSH, TCP/443 OpenVPN и UDP/443 WireGuard, а также established/related и необходимый control traffic. Политика forwarding сначала запрещает трафик между адресными пулами и интерфейсами VPN, затем разрешает трафик туннель→интернет через VPS и его обратные ответы. Она не вводит ограничений направлений или портов для VPS либо аутентифицированных VPN-клиентов.

Такой порядок даёт одну точку для межпротокольной IPv4/IPv6 изоляции, вместо разрозненных протокольных запретов. Аутентификация SSH и fail2ban остаются зоной `implement-secrets-and-administration`; этот change лишь оставляет SSH разрешённым входящим сервисом.

### Full tunnel, DNS и IPv6 preference

Каждый серверный протокол получает непересекающиеся IPv4 и IPv6 адресные пулы, default routes и DNS-настройки, применимые к нему. Реализация настраивает маршрут/NAT либо эквивалентную egress-механику по фактическим публичным интерфейсам хоста так, чтобы обе семьи проходили через VPS. Она рекламирует `1.1.1.1` перед `8.8.8.8`, но не запускает локальный DNS-процесс.

Настройка предпочтения IPv6 применяется только к исходящим соединениям, адресное семейство которых выбирает VPS. Для forwarded traffic она предоставляет рабочие IPv6 egress и IPv4 fallback, не блокируя и не задерживая IPv4. Альтернатива — попытка навязать IPv6 правилами сервера или proxy/NAT64 — не даёт контроля над выбором клиента и расширяет scope.

### Минимальный контракт public runtime state

`implement-device-lifecycle` атомарно публикует root-only состояние в `/var/lib/bastion/vpn`. Состояние содержит только:

- для WireGuard: public key пира и назначенные tunnel IPv4/IPv6 addresses;
- для OpenVPN: CA certificate, выданные public verification данные, CRL и public device metadata.

Точные protocol paths и сериализация выбираются при реализации совместимо с native services. Контракт запрещает CA private key и client private keys, а NixOS-конфигурации запрещено иметь параллельный статический список пиров или участников в `/nix/store` и system generations. Изменения этого состояния публикуются целиком; server-side hooks этого change применяют и проверяют уже опубликованное состояние. `implement-device-lifecycle` владеет механизмом публикации, live add/revoke и исходными records, поэтому обратной зависимости от этого change нет.

Для NixOS-тестов допускаются test-only public fixtures, заранее помещаемые в ту же границу состояния. Они проверяют серверное применение правил и не имитируют management CLI или генерацию credential.

### Параметры OpenVPN выбираются по актуальным данным

На этапе реализации проверяются официальный OpenVPN manual и документация выбранных версий NixOS/nixpkgs: поддержка cipher/auth, compression policy, control-channel protection и доступное acceleration. Выбор фиксируется рядом с конфигурацией и измеряется на целевом VPS-классе. Это лучше заранее закреплённого набора параметров из исторического Ansible, поскольку baseline требует безопасность и практическую производительность, но не конкретный устаревающий механизм.

## Risks / Trade-offs

- [Неверный egress interface, NAT или IPv6 prefix] → параметризовать хостовую сеть в platform change и проверить IPv4/IPv6 forwarding с test peers до readiness.
- [Firewall разрешит VPN peer-to-peer трафик из-за порядка правил] → отдельные IPv4/IPv6 проверки матрицы WireGuard↔WireGuard, OpenVPN↔OpenVPN и WireGuard↔OpenVPN до разрешения tunnel egress.
- [Некорректное или неполное public state при обновлении] → lifecycle публикует состояние атомарно; server hooks валидируют и применяют только завершённую версию, а конфигурация не содержит второго membership list.
- [OpenVPN настройки не поддержаны pinned версиями или превышают 1 vCPU] → сверить upstream в момент реализации, сохранить измерения throughput/CPU и не заявлять непроверенные пределы.
- [Успешная NixOS VM-проверка не доказывает публичную достижимость DNS] → до readiness выполнить и явно отчитаться о live checks обоих резолверов и обоих VPN через VPS.

## Migration Plan

1. После завершения platform и secrets changes добавить серверные сетевые и VPN-модули, не публикуя live membership state в Nix store.
2. Добавить public fixtures и NixOS checks для listener/firewall, туннельного IPv4/IPv6 forwarding, DNS-order, DNS reachability и peer isolation.
3. Провести build и NixOS component checks server-side consumer на public fixtures; полная orchestration-интеграция publish hook остаётся задачей владельца `implement-device-lifecycle` и не блокирует завершение этого change.
4. Передать `implement-recovery-and-updates` checklist для live throughput/DNS/connectivity и безопасного rollout. Фактические live checks, сохранение SSH-сессии и deployment выполняются только в шестом change после завершения всех foundations. Этот planning change ничего не развёртывает.
