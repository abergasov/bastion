# Секреты и административный доступ

Скопируйте `inventory/secrets-input.json.example` в игнорируемый
`inventory/secrets-input.json`. Он содержит только public owner/VPS age
recipients, public Ed25519 admin key, абсолютный local path к VPS age identity и
repo-relative path к SOPS ciphertext. `make bootstrap`, `apply` и `maintenance`
проверяют shape recipients, независимость owner/VPS, permissions `0600` identity,
recipient metadata и обязательные server secret names до подключения к host.

`secrets/server.yaml` — tracked SOPS ciphertext path in Git, not an ignored
plaintext input. Ignore only `inventory/secrets-input.json` and local identity
sources; a real server file must remain encrypted for both declared recipients.

Ciphertext и VPS identity копируются только как `root:root 0600`. Pinned x86_64
SOPS `v3.13.3` decrypts server inputs at boot/apply into `/run/secrets/bastion`;
the systemd service clears that directory first and SSH requires successful
decryption. Runtime paths for later changes are `/run/secrets/bastion/openvpn-server-key`
and `/run/secrets/bastion/wireguard-server-key`; ssh_notify adds its own complete
ciphertext and runtime file later. CA, client keys, enrollment and revocation
state must not be encrypted for the VPS.

Bootstrap creates `admin` and its public key while the provider session remains
usable. The first `make apply` must establish a fresh `admin` SSH connection and
assert its remote user before it writes/reloads final SSH restrictions. Then SSH
accepts only `admin` public-key login; root, password and keyboard-interactive
login are disabled. Routine automation becomes root through password-authenticated
`su`; no sudo is granted to admin. fail2ban enables the packaged Ubuntu SSH jail
without project retry, ban-duration, exemption, backend or firewall-policy overrides.

For approved Vault import, decrypt only in a protected temporary directory outside
this repository, transfer only required values to SOPS ciphertext, then remove
the temporary plaintext. Never copy the Vault password, SSH seed/private key, CA
or client state to the VPS. This remains local preparation, not live rollout.
The synthetic import contract test treats a read-only Vault view as its source,
selects exactly the four server values into a protected staging file, verifies the
source hash did not change, and rejects Vault password, SSH seed and owner-only
material before the staging file can become ciphertext.

## Проверка реализации

Источники pinned runtime: [SOPS v3.13.3](https://github.com/getsops/sops/releases/tag/v3.13.3)
и [age v1.3.2](https://github.com/FiloSottile/age/releases/tag/v1.3.2). Runtime
SOPS checksum проверяется ролью; Ubuntu 26.04 fixture установил `age 1.2.1-1build1`
и `fail2ban 1.1.0-9`. `ansible-core 2.21.5` использует documented
[su become method](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_privilege_escalation.html).

На disposable Ubuntu 26.04 QEMU TCG VM, без KVM и без доступа к VPS, проверены
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
