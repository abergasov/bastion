# Tasks

## 1. Подтвердить границы и upstream-интерфейсы

- [ ] 1.1 После готовности `implement-nixos-platform` зафиксировать точки импорта его host-модуля и потребителей из `implement-vpn-connectivity`, `implement-device-lifecycle` и `implement-ssh-notifications`; проверить документированную карту зависимостей и отсутствие второго SOPS bootstrap согласно [design.md](design.md#разделение-секретов-и-интерфейс-для-соседних-changes).
- [ ] 1.2 По официальным документации и option declarations закреплённой NixOS/nixpkgs, nixos-anywhere, sops-nix и fail2ban подтвердить поддерживаемые API для bootstrap VPS age identity, password-файлов, runtime ownership, SSH-лога и default SSH jail; сохранить ссылки и выбранные значения в implementation notes, не выдавая исторические наблюдения за актуальные.

## 2. Реализовать серверное хранение секретов

- [ ] 2.1 Добавить принадлежащий этому change минимальный provisioning hook, который до первой sops-nix activation по authenticated source-OS SSH с host-key verification создаёт или доставляет независимую VPS age identity в защищённый persistent path вне Git и `/nix/store`, получает verified recipient и останавливает secret provisioning при ошибке проверки; installer платформы только вызывает hook.
- [ ] 2.2 Добавить synthetic install fixture с VPS age identity и проверить порядок: verified recipient доступен до первой sops-nix activation, password material и server secrets расшифровываются без временного plaintext, а private identity не входит в Git, Nix build artifacts или `/nix/store`.
- [ ] 2.3 Добавить минимальный SOPS/age и sops-nix модуль для серверных секретов с независимыми owner/VPS recipients; проверить `nix flake check` без plaintext-значений и соответствие [Encrypted server VPN keys in Git](../../specs/recovery-and-verification/spec.md#requirement-encrypted-server-vpn-keys-in-git).
- [ ] 2.4 Добавить только зашифрованные fixtures/метаданные для VPN-ключей и password material `admin`/`root`; проверить статически, что Git не содержит private age identities, plaintext-паролей, токенов, CA или client private keys, согласно [Persistent credential state and protected secrets](../../specs/recovery-and-verification/spec.md#requirement-persistent-credential-state-and-protected-secrets).
- [ ] 2.5 Опубликовать для VPN именованные пути/контракт server-key runtime-файлов и добавить fixture, проверяющий их создание sops-nix и минимальные права без plaintext в Nix evaluation, derivation, логах или аргументах команд; фактическое подключение VPN-сервисов остаётся в `implement-vpn-connectivity`.
- [ ] 2.6 Написать focused проверку recipient separation: VPS может получить только server secrets, тогда как CA, client private keys и authoritative enrollment/revocation records отсутствуют во всех SOPS inputs и доступных VPS runtime-файлах; проверить требования [Owner-only age encryption of local credential state](../../specs/recovery-and-verification/spec.md#requirement-owner-only-age-encryption-of-local-credential-state) и [Local credential issuance and public server state](../../specs/device-lifecycle/spec.md#requirement-local-credential-issuance-and-public-server-state).
- [ ] 2.7 Опубликовать стабильные пути/имена серверных runtime-секретов для VPN и ssh_notify без добавления plaintext-конфигурации ssh_notify; проверить, что `implement-ssh-notifications` может подключить свой complete encrypted config, а `implement-device-lifecycle` не получает интерфейс для CA или клиентских ключей.

## 3. Реализовать административный доступ

- [ ] 3.1 Добавить `admin`, его существующий Ed25519 public key и применение защищённых password-файлов `admin`/`root`; проверить NixOS evaluation и требования [Initial account passwords and privilege elevation](../../specs/server-administration/spec.md#requirement-initial-account-passwords-and-privilege-elevation).
- [ ] 3.2 Настроить публичный SSH только для `admin` с public-key authentication, запретом password и keyboard-interactive authentication и отказом root/любому другому пользователю; проверить конфигурационный тест по [Public key-only SSH](../../specs/server-administration/spec.md#requirement-public-key-only-ssh).
- [ ] 3.3 Добавить focused NixOS integration test: authorised key выполняет свежий SSH login как `admin`, password login и direct root login отклоняются, `su` принимает верный root password и отвергает неверный; тест связывает эти результаты с [Initial account passwords and privilege elevation](../../specs/server-administration/spec.md#requirement-initial-account-passwords-and-privilege-elevation).

## 4. Реализовать и проверить fail2ban

- [ ] 4.1 Включить fail2ban и штатный SSH jail без project-specific override порогов, окон, длительностей, escalation или exemptions; проверить generated configuration и подключение к фактическому SSH-логу/firewall по [fail2ban protection for public SSH](../../specs/server-administration/spec.md#requirement-fail2ban-protection-for-public-ssh).
- [ ] 4.2 Добавить focused NixOS integration test для IPv4: вызвать контролируемые SSH failures, зафиксировать effective default policy закреплённой ревизии, подтвердить log matching, ban и восстановление доступа после unban.
- [ ] 4.3 Добавить отдельный focused NixOS integration test для IPv6 с теми же наблюдениями matching, default policy, ban и unban; результат должен доказать реальную обработку IPv6, а не только наличие конфигурации.

## 5. Завершить проверку и подготовить интеграцию

- [ ] 5.1 Запустить форматирование, статические проверки, `nix flake check` и build system closure выбранного host; приложить результаты или явно зафиксировать недоступные checks согласно [Build and integration verification](../../specs/recovery-and-verification/spec.md#requirement-build-and-integration-verification).
- [ ] 5.2 Передать `implement-recovery-and-updates` checklist сквозного gate: VPN использует server-key runtime paths, device management проходит `admin` SSH + `su`, ssh_notify читает свой SOPS runtime config; проверить, что handoff не включает issuance, ротацию или live rollout и не делает завершение этого change зависимым от реализации соседей.
- [ ] 5.3 Перед любым отдельно авторизованным rollout подготовить checklist сохранения активной administrative session, свежего SSH login и fallback recreation; проверить соответствие [Safe rollout within authorized scope](../../specs/recovery-and-verification/spec.md#requirement-safe-rollout-within-authorized-scope) без выполнения деплоя в рамках этого change.
