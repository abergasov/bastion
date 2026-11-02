#!/usr/bin/python3
"""Reduce an already protected legacy Vault view to Bastion server values."""

import subprocess
import sys
from pathlib import Path

import yaml


def password_hash(value: str) -> str:
    result = subprocess.run(
        ["openssl", "passwd", "-6", "-stdin"], input=value + "\n", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode or not result.stdout.strip():
        raise SystemExit("cannot derive SHA-512 password hash")
    return result.stdout.strip()


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: build-bastion-server-vault.py LEGACY_PLAINTEXT OUTPUT")
    try:
        legacy = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as error:
        raise SystemExit(f"cannot read protected legacy Vault view: {error}") from error
    approved = {"user_password", "root_password", "tg_token", "tg_chat"}
    if not isinstance(legacy, dict) or not approved.issubset(legacy):
        raise SystemExit("legacy Vault lacks an approved import field")
    if any(not isinstance(legacy[name], str) or not legacy[name] for name in {"user_password", "root_password", "tg_token"}):
        raise SystemExit("legacy Vault has an empty approved field")
    if not isinstance(legacy["tg_chat"], (str, int)) or not str(legacy["tg_chat"]):
        raise SystemExit("legacy Vault has an empty Telegram chat identifier")
    target = {
        "admin-password-hash": password_hash(legacy["user_password"]),
        "root-password-hash": password_hash(legacy["root_password"]),
        "ssh-notify-config": (
            "SSHLogFile = /var/log/auth.log\n"
            "ServerName = bastion\n"
            f"TelegramBotToken = {legacy['tg_token']}\n"
            f"TelegramNotifyChat = {legacy['tg_chat']}\n"
        ),
    }
    Path(sys.argv[2]).write_text(yaml.safe_dump(target, sort_keys=True), encoding="utf-8")


if __name__ == "__main__":
    main()
