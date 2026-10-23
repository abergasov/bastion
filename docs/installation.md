# Ubuntu foundation

Подготовьте VPS вручную с Ubuntu Server 26.04 LTS, публичными IPv4 и IPv6 и
публичным Ed25519 ключом владельца. Скопируйте
`inventory/hosts.ini.example` в игнорируемый `inventory/hosts.ini`, а
`inventory/known_hosts.example` — в игнорируемый `inventory/known_hosts`.
Запишите точный Ed25519 host key созданного VPS для `ansible_host`; приватный
ключ, пароли и пути к identity не находятся в inventory и не передаются Make.
Укажите `dns_servers` как непустой JSON list допустимых unicast resolver IP, например
`dns_servers='["1.1.1.1","2606:4700:4700::1111"]'`: это provider host resolver,
а не DNS policy будущих VPN клиентов. Private и link-local provider resolvers
допустимы; unspecified, multicast, broadcast и loopback адреса отклоняются.

Создайте изолированное Python-окружение и установите точную automation-зависимость:

```sh
python3 -m venv .venv
.venv/bin/pip install --only-binary=:all: --require-hashes -r requirements.txt
```

До любого Make path установите на control node `age` (для `age-keygen`) и
`sops v3.13.3` for Linux x86_64 from the
[official release](https://github.com/getsops/sops/releases/tag/v3.13.3).
Verify the downloaded executable SHA-256
`e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b` before
placing it on `PATH`. The local `sops` plus the local VPS age identity decrypt
each required server value to discarded output during preflight; failure stops
before Ansible contacts the host. This is a controller prerequisite, not a VPS
secret or deployment step.

`make bootstrap` — единственный initial path: его preflight до Ansible проверяет
входы, pinned SSH identity, Ubuntu 26.04 и root либо non-interactive sudo. Он не
форматирует диски, не заменяет ОС и не использует provider API.

Перед bootstrap подготовьте [зашифрованные секреты и входы администрирования](secrets-and-administration.md).
Bootstrap создаёт `admin`; routine `make apply` и `make maintenance` подключаются только как `admin` и
используют `su`; пароль запрашивается интерактивно и не передаётся аргументом.
`maintenance` — явственный путь для `apt upgrade`; обычный apply пакеты не
обновляет. Перед activation и ручным reboot сохраните текущую административную
сессию и проверьте свежий SSH доступ.

Этот foundation не авторизует live provisioning. SOPS/age и admin policy реализованы;
VPN, VPN firewall, ssh_notify и device lifecycle остаются в changes 3–5.

## Проверенные источники

Ubuntu публикует [26.04 LTS](https://documentation.ubuntu.com/release-notes/26.04/)
как LTS до апреля 2031; применён x86_64 Server baseline. Automation закреплена
на `ansible-core==2.21.5`; [матрица Ansible](https://docs.ansible.com/projects/ansible-core/devel/reference_appendices/release_and_maintenance.html)
указывает Python 3.12–3.14 на control node и Python 3.9–3.14 на target для 2.21.
Нужны только `ansible.builtin`, поэтому Galaxy collections отсутствуют. SHA-256
sdist: `65bb3148c58ebb843cd5074004c805f404f152114d98476dd823324616c9c6cb`;
wheel: `08886f9f3e23d129aa98a01271c4a47833516e1cb7c737a246788cb474f41222`
из [официального release v2.21.5](https://github.com/ansible/ansible/releases/tag/v2.21.5).
Проверка wheel без подстановки зависимостей: `pip download --no-deps
--require-hashes -r requirements-artifact.txt`.
