#!/usr/bin/env python3
"""Verify a new controller SSH authentication without reusing Ansible muxing."""

import json
import os
import re
import shlex
import subprocess
import sys


HOST_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.:-]*\Z")
USER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*\Z")


def fail(message: str) -> None:
    raise ValueError(message)


def split_option(value: object, name: str) -> list[str]:
    if not isinstance(value, str):
        fail(f"{name} must be a string")
    try:
        return shlex.split(value)
    except ValueError:
        fail(f"{name} is not valid SSH arguments")


def ssh_options(arguments: list[str]) -> list[str]:
    options: list[str] = []
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "-o":
            if index + 1 == len(arguments):
                fail("SSH -o option has no value")
            options.append(arguments[index + 1])
            index += 2
            continue
        if argument.startswith("-o") and len(argument) > 2:
            options.append(argument[2:])
        if argument == "-F":
            if index + 1 == len(arguments) or arguments[index + 1] != "/dev/null":
                fail("SSH configuration files are unsupported")
            index += 2
            continue
        if argument.startswith("-F") and len(argument) > 2:
            if argument[2:] != "/dev/null":
                fail("SSH configuration files are unsupported")
        if argument == "-i" or (argument.startswith("-i") and len(argument) > 2):
            fail("inline SSH private-key options are unsupported")
        index += 1
    return options


def option_key_value(option: str) -> tuple[str, str]:
    key, separator, value = option.partition("=")
    if not separator:
        parts = option.split(None, 1)
        key = parts[0]
        value = parts[1] if len(parts) == 2 else ""
    return key.lower(), value.lower()


def verify(data: dict[str, object]) -> tuple[list[str], str, str, int, str]:
    host = data.get("host")
    user = data.get("user")
    port = data.get("port")
    key = data.get("private_key_file", "")
    if not isinstance(host, str) or not HOST_RE.fullmatch(host):
        fail("host is unsupported")
    if not isinstance(user, str) or not USER_RE.fullmatch(user):
        fail("user is unsupported")
    if isinstance(port, bool) or not str(port).isdigit() or not 1 <= int(port) <= 65535:
        fail("port is unsupported")
    if not isinstance(key, str):
        fail("private key path is unsupported")
    if key and (not os.path.isfile(key) or not os.access(key, os.R_OK)):
        fail("private key is unavailable")

    arguments: list[str] = []
    for name in ("ssh_args", "ssh_common_args", "ssh_extra_args"):
        arguments.extend(split_option(data.get(name, ""), name))
    options = ssh_options(arguments)
    strict_options = [option_key_value(option) for option in options]
    strict_options = [value for key, value in strict_options if key == "stricthostkeychecking"]
    if not strict_options or any(value != "yes" for value in strict_options):
        fail("strict host-key checking is required")
    known_hosts = [value for key, value in (option_key_value(option) for option in options) if key == "userknownhostsfile"]
    if not known_hosts or any(not value or value == "/dev/null" for value in known_hosts):
        fail("a user known-hosts file is required")

    destination = f"{user}@{host}"
    if ":" in host:
        destination = f"{user}@[{host}]"
    return arguments, destination, key, int(port), host


def main() -> None:
    if len(sys.argv) not in (2, 3):
        raise SystemExit("usage: bastion-verify-fresh-ssh.py [--validate] JSON")
    validate_only = len(sys.argv) == 3
    if validate_only and sys.argv[1] != "--validate":
        raise SystemExit("usage: bastion-verify-fresh-ssh.py [--validate] JSON")
    raw = sys.argv[-1]
    try:
        data = json.loads(raw)
        if not isinstance(data, dict):
            fail("connection input must be an object")
        arguments, destination, key, port, _ = verify(data)
        if validate_only:
            return
        command = [
            "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
            "-o", "ControlMaster=no", "-o", "ControlPersist=no",
            "-o", "ControlPath=none", *arguments,
        ]
        if key:
            command.extend(["-i", key])
        command.extend(["-p", str(port), "--", destination, "true"])
        subprocess.run(command, check=True, timeout=20)
    except (ValueError, json.JSONDecodeError, subprocess.SubprocessError, OSError):
        raise SystemExit("fresh SSH verification failed")


if __name__ == "__main__":
    main()
