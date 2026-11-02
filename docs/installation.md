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
ansible-galaxy collection install -r collections/requirements.yml
```

До любого Make path установите `ansible-core` из `requirements.txt` и храните
controller-only Ansible Vault password source в
`/home/alejandro/go/src/ansible/vault.txt`. Preflight расшифровывает tracked
Vault только на controller для проверки schema; failure stops before Ansible
contacts a host. Password and ciphertext never become VPS material.

`make bootstrap` — единственный initial path: его preflight до Ansible проверяет
входы, pinned SSH identity, Ubuntu 26.04 и root либо non-interactive sudo. Он не
форматирует диски, не заменяет ОС и не использует provider API.

Make передаёт один и тот же strict SSH option set одновременно в
`--ssh-common-args` и JSON extra variable `ansible_ssh_common_args`. Это нужно
для независимой post-firewall SSH проверки без multiplexing. При прямом
`ansible-playbook` вызове передайте обе формы с теми же
`StrictHostKeyChecking=yes` и `UserKnownHostsFile=inventory/known_hosts`;
отсутствующее или небезопасное значение намеренно останавливает apply до UFW
mutation.

Перед bootstrap подготовьте [зашифрованные секреты и входы администрирования](secrets-and-administration.md).
Bootstrap создаёт `admin`; routine `make apply` и `make maintenance` подключаются только как `admin` и
используют `su`; пароль запрашивается интерактивно и не передаётся аргументом.
`maintenance` — явственный путь для `apt upgrade`; обычный apply пакеты не
обновляет. Перед activation и ручным reboot сохраните текущую административную
сессию и проверьте свежий SSH доступ.

Этот foundation не авторизует live provisioning. Controller-only Vault и admin policy реализованы;
VPN, VPN firewall, ssh_notify и device lifecycle остаются в changes 3–5.

## Проверенные источники

Ubuntu публикует [26.04 LTS](https://documentation.ubuntu.com/release-notes/26.04/)
как LTS до апреля 2031; применён x86_64 Server baseline. Automation закреплена
на `ansible-core==2.21.5`; [матрица Ansible](https://docs.ansible.com/projects/ansible-core/devel/reference_appendices/release_and_maintenance.html)
указывает Python 3.12–3.14 на control node и Python 3.9–3.14 на target для 2.21.
Помимо `ansible-core`, firewall role требует закреплённую Galaxy collection
`community.general==13.5.0` из `collections/requirements.yml`; до syntax, VM
или apply установите её через приведённую команду. SHA-256
sdist: `65bb3148c58ebb843cd5074004c805f404f152114d98476dd823324616c9c6cb`;
wheel: `08886f9f3e23d129aa98a01271c4a47833516e1cb7c737a246788cb474f41222`
из [официального release v2.21.5](https://github.com/ansible/ansible/releases/tag/v2.21.5).
Проверка wheel без подстановки зависимостей: `pip download --no-deps
--require-hashes -r requirements-artifact.txt`.
