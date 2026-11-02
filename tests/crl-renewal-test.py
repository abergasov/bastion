#!/usr/bin/env python3
"""Synthetic checks for CRL identity/revocation semantics and the manual VPS path."""
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_loader("lifecycle", SourceFileLoader(
    "lifecycle", str(ROOT / "scripts/bastion-vpn-lifecycle")))
lifecycle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lifecycle)


def state() -> dict:
    return {"version": 1, "endpoint": "vpn.example", "revocations": [], "pki": {},
            "wireguard": {"server_private": "A" * 43 + "=", "server_public": "B" * 43 + "=", "clients": {}},
            "openvpn": {"clients": {}}}


def crl_next_update(contents: str) -> float:
    with tempfile.TemporaryDirectory(prefix="bastion-crl-date.") as temporary:
        crl = Path(temporary) / "crl.pem"
        crl.write_text(contents)
        value = subprocess.check_output(["openssl", "crl", "-in", str(crl), "-noout", "-nextupdate"], text=True).strip().split("=", 1)[1]
    return datetime.strptime(value, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc).timestamp()


class CrlRenewalTest(unittest.TestCase):
    def authority_with_revocation(self) -> tuple[dict, str]:
        authority = state()
        with tempfile.TemporaryDirectory(prefix="bastion-crl-fixture.") as temporary:
            directory = Path(temporary)
            (directory / "newcerts").mkdir()
            (directory / "index.txt").write_text("")
            (directory / "serial").write_text("1000\n")
            (directory / "crlnumber").write_text("1000\n")
            lifecycle.run(["openssl", "req", "-x509", "-new", "-nodes", "-newkey", "rsa:2048", "-keyout", str(directory / "ca.key"), "-out", str(directory / "ca.crt"), "-days", "3650", "-sha256", "-subj", "/CN=renewal-test-ca"])
            lifecycle.issue_server(directory)
            lifecycle.capture_pki(authority, directory)
        lifecycle.add_open(authority, "revoked")
        revoked_certificate = authority["openvpn"]["clients"]["revoked"]["cert"]
        lifecycle.add_open(authority, "active")
        lifecycle.revoke_open(authority, "revoked")
        return authority, revoked_certificate

    def test_renewal_preserves_identities_and_revoked_client_denial(self):
        authority, revoked_certificate = self.authority_with_revocation()
        identities = {key: authority["pki"][key] for key in ("ca.key", "ca.crt", "server.key", "server.crt")}
        active = authority["openvpn"]["clients"]["active"].copy()
        index, revocations = authority["pki"]["index.txt"], list(authority["revocations"])
        lifecycle.renew_open_crl(authority)
        self.assertEqual({key: authority["pki"][key] for key in identities}, identities)
        self.assertEqual(authority["pki"]["index.txt"], index)
        self.assertEqual(authority["revocations"], revocations)
        self.assertGreater(crl_next_update(authority["pki"]["crl.pem"]), datetime.now(timezone.utc).timestamp())
        with tempfile.TemporaryDirectory(prefix="bastion-crl-verify.") as temporary:
            directory = Path(temporary)
            for name, contents in (("crl.pem", authority["pki"]["crl.pem"]), ("ca.crt", authority["pki"]["ca.crt"]), ("active.crt", active["cert"]), ("revoked.crt", revoked_certificate)):
                (directory / name).write_text(contents)
            subprocess.run(["openssl", "verify", "-crl_check", "-CAfile", str(directory / "ca.crt"), "-CRLfile", str(directory / "crl.pem"), str(directory / "active.crt")], check=True)
            revoked = subprocess.run(["openssl", "verify", "-crl_check", "-CAfile", str(directory / "ca.crt"), "-CRLfile", str(directory / "crl.pem"), str(directory / "revoked.crt")], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        self.assertNotEqual(revoked.returncode, 0)
        self.assertIn("certificate revoked", revoked.stderr)

    def test_manual_renewal_uses_admin_ssh_and_root_vps_command_only(self):
        original = lifecycle.interactive, lifecycle.vault_password, lifecycle.renew_open_crl, sys.argv
        commands = []
        try:
            lifecycle.interactive = lambda command: commands.append(command)
            lifecycle.vault_password = lambda: (_ for _ in ()).throw(AssertionError("controller Vault used"))
            lifecycle.renew_open_crl = lambda authority: (_ for _ in ()).throw(AssertionError("controller signed CRL"))
            sys.argv = ["bastion-vpn-lifecycle", "renew-open", "--vpn-host", "vpn.example"]
            self.assertEqual(lifecycle.main(), 0)
        finally:
            lifecycle.interactive, lifecycle.vault_password, lifecycle.renew_open_crl, sys.argv = original
        self.assertEqual(commands[0][:2], ["ssh", "-tt"])
        self.assertIn("admin@vpn.example", commands[0])
        self.assertIn("su -c", commands[0][-1])
        self.assertIn("bastion-vpn-renew-crl --activate", commands[0][-1])

    def test_manual_renewal_leaves_pending_controller_authority_untouched(self):
        authority = state()
        authority["pki"]["crl.pem"] = "EXPIRED"
        authority["pending"] = {"action": "add-wg", "device": "phone", "server_keys_pending": False}
        original = lifecycle.interactive, lifecycle.vault_password, sys.argv
        try:
            with tempfile.TemporaryDirectory(prefix="bastion-crl-pending.") as temporary:
                ciphertext = Path(temporary) / "authority.yaml"
                ciphertext.write_text(json.dumps(authority))
                lifecycle.interactive = lambda command: None
                lifecycle.vault_password = lambda: (_ for _ in ()).throw(AssertionError("controller Vault used"))
                sys.argv = ["bastion-vpn-lifecycle", "renew-open", "--vpn-host", "vpn.example", "--workdir", temporary, "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 0)
                self.assertEqual(json.loads(ciphertext.read_text())["pending"], authority["pending"])
        finally:
            lifecycle.interactive, lifecycle.vault_password, sys.argv = original


if __name__ == "__main__":
    unittest.main()
