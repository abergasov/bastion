# Установка foundation

Foundation ещё не разрешает live-установку. Сначала должны быть завершены changes
2–5 и внешний integration gate; `implement-recovery-and-updates` определит
manual-update workflow.

После отдельного разрешения создайте VPS в панели провайдера с публичными IPv4 и
IPv6 и добавьте публичный Ed25519 SSH-ключ владельца. Скопируйте
`hosts/bastion/host-input.nix.example` в игнорируемый `host-input.nix`, затем
внесите публичные IPv4/IPv6, маршруты и полный ожидаемый Ed25519 host key
исходной ОС. Приватный SSH-ключ не записывается в этот репозиторий и не
передаётся аргументом Make; используйте обычный ssh-agent или SSH config.

Обычная Nix evaluation Git-flake не включает игнорируемый local input. Поэтому
installer после preflight создаёт удаляемую локальную копию flake, modules,
hosts, patch и encrypted SOPS ciphertext и запускает там `--flake .#bastion`. Это применяет
локальный input без `git add -f` и без риска случайного коммита.

`make install-bastion` сначала подключается к source OS в batch mode с временным
known_hosts, содержащим только заданный key, и проверяет `id -u == 0` либо
`sudo -n true`. Затем `bootstrap-vps-age` проверяет уже созданную локальную VPS
age identity и expected recipient, staging’ит только identity mode `0600` как
`/var/lib/sops-nix/age/key.txt` через `--extra-files`, и лишь затем запускается
`nixos-anywhere`. Полный operator flow указан в
[secrets-and-administration.md](secrets-and-administration.md).

Доступ к source OS нужен только для переустановки. Этот change добавляет
admin-only SSH и sops-nix interface, но не является разрешением на установку:
VM checks и итоговый recovery gate ещё обязательны.
