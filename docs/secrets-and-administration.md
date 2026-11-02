# Секреты и административный доступ

Целевая модель держит CA private key, клиентские приватные ключи, полную
authority, SSH private key администратора и пароль Vault только на controller.
VPS получает подписанный CRL и public records, но не CA key, его projection,
renewal service или timer. При подтверждённом старом exposure CA нужны новый CA
и profiles; обычная VPS compromise без такого exposure этого не требует.

Скопируйте `inventory/secrets-input.json.example` в игнорируемый
`inventory/secrets-input.json`. Он содержит public Ed25519 admin key, абсолютный
controller-only `vault_password_file` и repo-relative `vault_secrets_file`.
Пароль Vault используется только на controller; согласованный read-only источник
`/home/alejandro/go/src/ansible/vault.txt` имеет допустимый mode `0644`.

`secrets/server.yaml` — tracked Ansible Vault ciphertext, а не plaintext input.
`make bootstrap`, `apply` и `maintenance` расшифровывают его только на controller
и доставляют отдельные required files как `root:root 0600` в
`/var/lib/bastion/secrets` (каталог `0700`). Boot activation атомарно заменяет
`/run/secrets/bastion`; Vault password и ciphertext на VPS не попадают. Runtime
paths remain `/run/secrets/bastion/openvpn-server-key`,
`/run/secrets/bastion/wireguard-server-key` and
`/run/secrets/bastion/ssh-notify.conf`. CA key, client keys, SSH seeds and the
full authority remain excluded. Public enrollment/revocation data and the signed
CRL are deployed separately.

Bootstrap creates `admin` and its public key while the provider session remains
usable. The first `make apply` must establish a fresh `admin` SSH connection and
assert its remote user before it writes/reloads final SSH restrictions. Then SSH
accepts only `admin` public-key login; root, password and keyboard-interactive
login are disabled. Routine automation becomes root through password-authenticated
`su`; no sudo is granted to admin. fail2ban enables the packaged Ubuntu SSH jail
without project retry, ban-duration, exemption, backend or firewall-policy overrides.

For approved Vault import, decrypt only in a protected temporary directory outside
this repository, transfer only required values to Ansible Vault ciphertext, then remove
the temporary plaintext. Never copy the Vault password, CA key, SSH seed/private
key, client private state or the full authority to the VPS. This remains local
preparation, not live rollout.
The synthetic import contract test treats a read-only Vault view as its source,
selects exactly the four server values into a protected staging file, verifies the
source hash did not change, and rejects Vault password, SSH seed and owner-only
material before the staging file can become ciphertext.

## Проверка реализации

Runtime uses Ansible Vault only on the controller; no SOPS or age package is
required on the VPS. `ansible-core 2.21.5` uses documented
[su become method](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_privilege_escalation.html).

Historical note: the following recipient/age VM evidence predates Vault and is
not current verification. На disposable Ubuntu 26.04 QEMU TCG VM, без KVM и без доступа к VPS, проверены
initial apply, repeat apply без изменений, reboot, permissions runtime files,
owner/VPS decrypt server ciphertext, отказ unrelated recipient и отказ VPS для
owner-only CA/client fixture. Synthetic corrupt ciphertext очищает runtime и
не даёт secrets/SSH service стартовать; восстановление ciphertext возвращает
доступ. Проверены fresh `admin` public-key login, отказы root/other user/password/
keyboard-interactive и valid/invalid password-authenticated `su`.

Native SSH jail fail2ban оставлен без project overrides. Effective Ubuntu defaults
в VM: `maxretry=5`, `findtime=600`, `bantime=600`, journal match
`_SYSTEMD_UNIT=ssh.service + _COMM=sshd`. The `+` is journal disjunction, so
`sshd-session` records from `ssh.service` are included. Five paced synthetic
`Invalid user` attempts from an isolated in-guest veth/netns peer caused automatic
ban for each family: IPv6 `fd42:5::2` to `fd42:5::1`, then IPv4 `198.18.0.2` to
`198.18.0.1`. A known-valid synthetic admin key was refused while each peer was
banned; native `unbanip` restored that same access and left no active bans.

`make test`, all three playbook syntax checks, `ansible-lint` and `git diff --check`
also pass. These are synthetic isolated checks only: no Vault data, real SSH key,
live VPS, VPN service, certificate lifecycle or rollout was used or declared ready.
