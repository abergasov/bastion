#!/usr/bin/env python3
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "fresh_ssh", ROOT / "roles/firewall/files/bastion-verify-fresh-ssh.py"
)
fresh_ssh = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(fresh_ssh)


class FreshSshTest(unittest.TestCase):
    def payload(self, key: str) -> dict[str, object]:
        return {
            "host": "vpn.example",
            "port": 22,
            "user": "admin",
            "private_key_file": key,
            "ssh_args": "-o ControlMaster=auto",
            "ssh_common_args": "-o StrictHostKeyChecking=yes -o UserKnownHostsFile=/tmp/known_hosts -J jump.example",
            "ssh_extra_args": "-o ServerAliveInterval=30",
        }

    def invoke(self, *arguments: str) -> None:
        with patch.object(sys, "argv", ["fresh-ssh", *arguments]):
            fresh_ssh.main()

    def test_no_mux_options_precede_existing_ssh_args(self) -> None:
        with tempfile.NamedTemporaryFile() as key:
            calls = []
            with patch.object(fresh_ssh.subprocess, "run", side_effect=lambda *args, **kwargs: calls.append((args, kwargs))):
                self.invoke(json.dumps(self.payload(key.name)))
        command = calls[0][0][0]
        self.assertEqual(
            command[:11],
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ControlMaster=no", "-o", "ControlPersist=no", "-o", "ControlPath=none"],
        )
        self.assertLess(command.index("ControlMaster=no"), command.index("ControlMaster=auto"))
        self.assertEqual(command[-3:], ["--", "admin@vpn.example", "true"])
        self.assertTrue(calls[0][1]["check"])
        self.assertEqual(calls[0][1]["timeout"], 20)

    def test_rejects_malformed_and_insecure_arguments(self) -> None:
        with tempfile.NamedTemporaryFile() as key:
            malformed = self.payload(key.name)
            malformed["ssh_common_args"] = "-o 'unterminated"
            with self.assertRaises(SystemExit):
                self.invoke("--validate", json.dumps(malformed))
            insecure = self.payload(key.name)
            insecure["ssh_common_args"] = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/known_hosts"
            with self.assertRaises(SystemExit):
                self.invoke("--validate", json.dumps(insecure))
            for strict_option in ("accept-new", "off", "no"):
                ordered = self.payload(key.name)
                ordered["ssh_args"] = f"-o StrictHostKeyChecking={strict_option}"
                with self.assertRaises(SystemExit):
                    self.invoke("--validate", json.dumps(ordered))
                ordered["ssh_args"] = f"-o 'StrictHostKeyChecking {strict_option}'"
                with self.assertRaises(SystemExit):
                    self.invoke("--validate", json.dumps(ordered))
            config = self.payload(key.name)
            config["ssh_args"] = "-F /tmp/ssh-config"
            with self.assertRaises(SystemExit):
                self.invoke("--validate", json.dumps(config))
            null_known_hosts = self.payload(key.name)
            null_known_hosts["ssh_args"] = "-o 'UserKnownHostsFile /dev/null'"
            with self.assertRaises(SystemExit):
                self.invoke("--validate", json.dumps(null_known_hosts))

    def test_rejects_failed_fresh_ssh_authentication(self) -> None:
        with tempfile.NamedTemporaryFile() as key:
            with patch.object(
                fresh_ssh.subprocess,
                "run",
                side_effect=subprocess.CalledProcessError(255, "ssh"),
            ):
                with self.assertRaises(SystemExit):
                    self.invoke(json.dumps(self.payload(key.name)))


if __name__ == "__main__":
    unittest.main()
