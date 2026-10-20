# Секреты и административный доступ

Этот change добавляет интерфейс, но не готовит Bastion к установке или rollout.
До `make install-bastion` оператор локально создаёт независимую VPS age identity
с mode `0600`, получает её public recipient через `age-keygen -y`, сверяет его с
`vpsAgeRecipient` в игнорируемом `hosts/bastion/host-input.nix`, добавляет оба
public recipients в `.sops.yaml` и шифрует `secrets/server.yaml` через sops.
Приватная identity владельца остаётся вне репозитория и VPS. Приватная identity
VPS остаётся вне Git и `/nix/store`.

`host-input.nix` содержит только `adminAuthorizedKey`, оба public recipients,
локальный путь к VPS identity и относительный путь к ciphertext. При этих четырёх
входах модуль включает sops-nix. Обычный checkout использует null template и не
активирует секреты. `scripts/install-bastion` выполняет уже существующий SSH
host-key/privilege preflight и только затем вызывает `bootstrap-vps-age`. Hook
проверяет соответствие private identity и expected recipient, копирует identity
как `var/lib/sops-nix/age/key.txt` mode `0600` во временный `--extra-files` tree,
а ciphertext — в временную копию flake. Ошибка отсутствующего входа, режима или
recipient, отсутствующего или не-SOPS ciphertext останавливает installer до
`nixos-anywhere`: hook сверяет оба recipient в metadata и расшифровывает каждый
обязательный key в `/dev/null` уже staged VPS identity.

В Git лежит только metadata fixture [server.yaml](../secrets/server.yaml); она
намеренно не зашифрована и не может быть расшифрована или активирована. Перед
production configuration её заменяют SOPS ciphertext, содержащим только
`admin-password-hash`, `root-password-hash`, `openvpn-server-key` и
`wireguard-server-key`. CA, client private keys, issuance и authoritative
enrollment/revocation records сюда не входят. `.sops.yaml.example` показывает
двух-recipient rule без private identity.

Модуль предоставляет будущим changes только следующие runtime paths:

| Consumer | Path |
| --- | --- |
| `implement-vpn-connectivity` | `/run/secrets/openvpn-server-key`, `/run/secrets/wireguard-server-key` |
| `implement-ssh-notifications` | `/run/secrets/ssh-notify-config` после добавления им complete encrypted config |
| `implement-device-lifecycle` | admin SSH, затем `su` с root password; без интерфейса CA/client secrets |

`admin` получает supplied Ed25519 public key и password hash из
`/run/secrets-for-users`; SSH разрешает только `admin` public-key login. Root
elevation остаётся через `su`; sudo не добавляется. fail2ban включён без
переопределения jail. Для pinned NixOS 26.05 recorded defaults: systemd backend,
`maxretry = 3`, `findtime = 10m`, `bantime = 10m`; integration test получает
`maxretry` runtime, а не фиксирует проектское значение.

Проверенные API: [sops-nix options](https://github.com/Mic92/sops-nix/blob/44931708c62937c2b1bf7953902989fa5bb9ee1b/modules/sops/default.nix),
[nixos-anywhere extra files](https://github.com/nix-community/nixos-anywhere/blob/bad98b0685cf47eaeadcaf6787da8b51cf025693/src/nixos-anywhere.sh),
[NixOS OpenSSH](https://search.nixos.org/options?channel=26.05&show=services.openssh.settings),
and [NixOS fail2ban](https://search.nixos.org/options?channel=26.05&show=services.fail2ban.enable).

Перед отдельно авторизованным rollout сохранить текущую admin session, проверить
fresh public-key SSH login и `su`, затем иметь готовый recreation fallback. VPN
runtime paths, device management и ssh_notify являются cross-component gate для
`implement-recovery-and-updates`; этот документ не разрешает issuance, rotation
или rollout.

## Локальная проверка

`make test` (включая static secret scan), `git diff --check` и strict OpenSpec
validation завершились успешно. На выделенной изолированной test node успешно
выполнены `nix fmt`, `nix flake check --no-build`, build host closure и полная
`nix flake check`. Полный NixOS integration test `admin-security` завершился
успешно под TCG без KVM: owner recipient расшифровал fixture, rejected identity
получила отказ; sops-nix создал ровно два server-key runtime-файла и protected
password files с нужными правами; key-only `admin` SSH, отказы root/password и
correct/incorrect `su` проверены. Штатный fail2ban SSH jail использовал systemd
journal match и свои pinned defaults; отдельные IPv4 и IPv6 invalid-user
attempts были забанены, authorised admin key был отклонён во время ban и снова
допущен после exact unban.

Это изолированная VM-проверка: Bastion не устанавливался и не развёртывался на
test node, а production secrets, VPN services, issuance, rotation и rollout
остаются вне этого change.
