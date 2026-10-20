# Tasks

## 1. Зафиксировать совместимый NixOS фундамент

- [x] 1.1 До изменения зависимостей проверить по официальным источникам актуальный stable NixOS, соответствующую ветку nixpkgs и совместимость `disko`/`nixos-anywhere`; записать выбранные refs в `flake.nix` и проверить результат `nix flake metadata` (требование: [воспроизводимый сервер](../../../specs/server-platform/spec.md#requirement-reproducible-nixos-server)).
- [x] 1.2 Добавить `flake.lock` и единственный x86_64 `nixosConfigurations` output с малым набором общих и host-модулей; проверить синтаксис и input graph командой `nix flake check` (требование: [воспроизводимый сервер](../../../specs/server-platform/spec.md#requirement-reproducible-nixos-server)).

## 2. Описать host и диск декларативно

- [x] 2.1 Добавить общий platform-модуль и отдельные Nix-модули первого host для provider-specific boot, сети и диска; реализовать baseline-поддержку Hetzner на первом этапе, не связывая общие модули с Hetzner API; не включать SSH/fail2ban, VPN, секреты, членство или уведомления из changes 2–5; проверить evaluation `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` (требования: [provider-independent host](../../../specs/server-platform/spec.md#requirement-provider-independent-host-configuration), [public addressing and installation](../../../specs/server-platform/spec.md#requirement-public-addressing-and-automated-installation)).
- [x] 2.2 Описать разметку и форматирование диска только через `disko`, с явно заданным target-диском, и проверить построение host closure `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` без доступа к VPS (требование: [public addressing and installation](../../../specs/server-platform/spec.md#requirement-public-addressing-and-automated-installation)).
- [x] 2.3 Добавить игнорируемый локальный host-input с IPv4, IPv6 и ожидаемым SSH host key и коммитируемый шаблон без реальных значений; проверить, что шаблон загружается, а `.gitignore` исключает только локальный input и `rg` не находит приватный ключ или конкретный host key в отслеживаемых файлах (требования: [public addressing and installation](../../../specs/server-platform/spec.md#requirement-public-addressing-and-automated-installation), [secret exposure](../../../specs/recovery-and-verification/spec.md#requirement-persistent-credential-state-and-protected-secrets)).

## 3. Дать безопасную локальную установку

- [x] 3.1 Добавить одну локальную Make-цель установки, которая читает host input, до форматирования проверяет совпадение SSH host key и привилегии source OS, затем вызывает `nixos-anywhere` с host-конфигурацией; покрыть ветки mismatch и отсутствующих привилегий focused test с подменёнными `ssh`/`nixos-anywhere`, подтверждающим, что disk command не запускается (требование: [public addressing and installation](../../../specs/server-platform/spec.md#requirement-public-addressing-and-automated-installation)).
- [x] 3.2 Документировать ручное создание VPS с IPv4/IPv6 и публичным Ed25519 ключом, заполнение локального input и границу между source-OS доступом и будущей admin-only политикой; проверить документацию командой без сетевых действий и убедиться, что она не содержит секретов (требования: [public addressing and installation](../../../specs/server-administration/spec.md#requirement-public-key-only-ssh)).

## 4. Настроить retention и ресурсный интерфейс

- [x] 4.1 Настроить нативное удержание system journal на 30 дней и место расширения для ротации текстового auth-log, если его добавит `implement-ssh-notifications`; проверить Nix evaluation выбранных настроек и отсутствие отдельного logging/metrics сервиса (требование: [default logs](../../../specs/server-platform/spec.md#requirement-default-logs-with-automatic-retention)).
- [x] 4.2 Добавить шаблон фиксации ресурсов VPS: память, свободный диск, throughput, наличие swap и непроверенные ограничения; проверить, что документ не задаёт процедуру update/activation и не обещает automatic updates или внешний builder (требование: [small VPS resource target](../../../specs/server-platform/spec.md#requirement-small-vps-resource-target)).

## 5. Проверить готовность foundation

- [x] 5.1 Запустить форматирование выбранным Nix formatter, `nix flake check` и build system closure первого host; сохранить результаты и явно отметить, что Nix evaluation, build и VM/live tests до этой реализации не выполнялись (требования: [reproducible server](../../../specs/server-platform/spec.md#requirement-reproducible-nixos-server), [build and integration verification](../../../specs/recovery-and-verification/spec.md#requirement-build-and-integration-verification)).
- [x] 5.2 Проверить Make installer в safe local test и зафиксировать handoff: foundation готов независимо от changes 2–5, а полный host build, VPN/SSH проверки, установка на VPS и manual-update workflow находятся во внешнем integration gate и в `implement-recovery-and-updates` (требования: [public addressing and installation](../../../specs/server-platform/spec.md#requirement-public-addressing-and-automated-installation), [server connectivity](../../../specs/recovery-and-verification/spec.md#requirement-server-connectivity-and-live-operation-verification)).
