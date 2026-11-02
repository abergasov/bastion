# Proposal

## Why

Владелец заменил SOPS/age на уже используемый Ansible Vault. Прежняя схема
требует VPS identity для расшифрования после загрузки, что несовместимо с новым
правилом: пароль Vault и controller secrets никогда не передаются на VPS.

## What Changes

- **BREAKING:** заменить SOPS/age ciphertext серверных и owner-only lifecycle
  secrets на Ansible Vault ciphertext с controller-only password source.
- Доставлять только необходимые серверу секреты из controller-side Vault в
  root-only persistent storage; после boot atomically восстанавливать прежний
  `/run/secrets` contract без Vault key на VPS.
- Импортировать из legacy Vault лишь нужные passwords и Telegram values;
  сохранить fresh OpenVPN identity и запретить перенос seed, CA и client keys.
- Перевести lifecycle/recovery rotation, preflight, VM/static checks,
  documentation and active implementation plans на Vault semantics.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `recovery-and-verification`: Vault storage, controller delivery, persistence
  after reboot and compromise/recovery rules replace SOPS/age recipient rules.
- `device-lifecycle`: owner authority and server-key lifecycle use Vault without
  exposing owner-only keys to the VPS.
- `server-administration`: account-password delivery uses controller-side Vault.
- `ssh-notifications`: complete application configuration uses Vault and
  protected persistent/runtime files without Telegram values in arguments.

## Impact

Affected roles, playbooks, preflight/lifecycle scripts, encrypted secret inputs,
systemd activation, tests, operator documentation and active OpenSpec plans.
Archived changes remain historical. No deployment, VPS mutation or Telegram
delivery is part of this change.
