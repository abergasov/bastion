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
installer после preflight создаёт удаляемую локальную копию только flake,
modules, hosts и patch и запускает там `--flake .#bastion`. Это применяет
локальный input без `git add -f` и без риска случайного коммита.

`make install-bastion` сначала подключается к source OS в batch mode с временным
known_hosts, содержащим только заданный key, и проверяет `id -u == 0` либо
`sudo -n true`. Лишь затем запускается `nixos-anywhere` с `--flake .#bastion`.

Доступ к source OS нужен только для переустановки. Политика установленного
Bastion (`admin`-only SSH и дальнейшие правила) будет добавлена отдельным
change, поэтому этот foundation нельзя считать готовым сервером.
