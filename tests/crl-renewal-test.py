#!/usr/bin/env python3
"""Synthetic checks for controller-issued OpenVPN CRLs."""
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import sys
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_loader("lifecycle", SourceFileLoader(
    "lifecycle", str(ROOT / "scripts/bastion-vpn-lifecycle")))
lifecycle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lifecycle)


def date_from(command: list[str], contents: str, field: str) -> datetime:
    with tempfile.TemporaryDirectory(prefix="bastion-crl-date.") as temporary:
        material = Path(temporary) / "material.pem"
        material.write_text(contents)
        value = subprocess.check_output([*command, "-in", str(material), "-noout", field], text=True).strip().split("=", 1)[1]
    return datetime.strptime(value, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)


class ControllerCrlTest(unittest.TestCase):
    def authority(self) -> dict:
        with tempfile.TemporaryDirectory(prefix="bastion-crl-fixture.") as temporary:
            directory = Path(temporary)
            (directory / "newcerts").mkdir()
            (directory / "index.txt").write_text("")
            (directory / "serial").write_text("1000\n")
            (directory / "crlnumber").write_text("1000\n")
            lifecycle.run(["openssl", "req", "-x509", "-new", "-nodes", "-newkey", "rsa:2048", "-keyout", str(directory / "ca.key"), "-out", str(directory / "ca.crt"), "-days", "3650", "-sha256", "-subj", "/CN=controller-crl-test-ca"])
            lifecycle.issue_server(directory)
            authority = {"version": 1, "endpoint": "vpn.example", "membership_revision": 1, "revocations": [], "pki": {},
                         "wireguard": {"server_private": "A" * 43 + "=", "server_public": "B" * 43 + "=", "clients": {}},
                         "openvpn": {"clients": {}}}
            lifecycle.capture_pki(authority, directory)
        return authority

    def test_initial_crl_is_bounded_by_ca_and_certificates_remain_finite(self):
        authority = self.authority()
        next_update = date_from(["openssl", "crl"], authority["pki"]["crl.pem"], "-nextupdate")
        ca_expiry = date_from(["openssl", "x509"], authority["pki"]["ca.crt"], "-enddate")
        cert_expiry = date_from(["openssl", "x509"], authority["pki"]["server.crt"], "-enddate")
        self.assertLessEqual(next_update, ca_expiry)
        self.assertGreater(next_update, datetime.now(timezone.utc) + timedelta(days=3600))
        self.assertLess(cert_expiry, datetime.now(timezone.utc) + timedelta(days=900))

    def test_revoke_retains_all_prior_revocations_in_a_locally_signed_crl(self):
        authority = self.authority()
        lifecycle.add_open(authority, "first")
        first = authority["openvpn"]["clients"]["first"]["cert"]
        lifecycle.add_open(authority, "second")
        second = authority["openvpn"]["clients"]["second"]["cert"]
        lifecycle.revoke_open(authority, "first")
        lifecycle.revoke_open(authority, "second")
        with tempfile.TemporaryDirectory(prefix="bastion-crl-verify.") as temporary:
            directory = Path(temporary)
            for name, contents in (("crl.pem", authority["pki"]["crl.pem"]), ("ca.crt", authority["pki"]["ca.crt"]),
                                   ("first.crt", first), ("second.crt", second)):
                (directory / name).write_text(contents)
            subprocess.run(["openssl", "crl", "-in", str(directory / "crl.pem"), "-noout", "-verify", "-CAfile", str(directory / "ca.crt")], check=True)
            for certificate in ("first.crt", "second.crt"):
                rejected = subprocess.run(["openssl", "verify", "-crl_check", "-CAfile", str(directory / "ca.crt"), "-CRLfile", str(directory / "crl.pem"), str(directory / certificate)], stderr=subprocess.PIPE, text=True, check=False)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("certificate revoked", rejected.stderr)

    def legacy_authority(self) -> dict:
        authority = self.authority()
        with tempfile.TemporaryDirectory(prefix="bastion-crl-legacy.") as temporary:
            directory = Path(temporary)
            lifecycle.pki_dir(authority, directory)
            lifecycle.run(["openssl", "ca", "-config", str(lifecycle.config(directory)), "-gencrl", "-crldays", "30", "-out", str(directory / "crl.pem")])
            lifecycle.capture_pki(authority, directory)
        return authority

    def test_legacy_sequence_is_seeded_upward_before_replacement(self):
        authority = self.legacy_authority()
        original = lifecycle.remote_crl_sequence
        lifecycle.remote_crl_sequence = lambda endpoint: 0x2000
        try:
            lifecycle.migrate_legacy_crl_sequence(authority, "vpn.example")
        finally:
            lifecycle.remote_crl_sequence = original
        self.assertGreater(lifecycle.crl_sequence(authority["pki"]["crl.pem"]), 0x2000)
        self.assertFalse(lifecycle.needs_long_lived_crl(authority))

    def test_legacy_sequence_rollback_fails_closed(self):
        authority = self.legacy_authority()
        original = lifecycle.remote_crl_sequence
        lifecycle.remote_crl_sequence = lambda endpoint: 0x100
        try:
            with self.assertRaises(lifecycle.Error):
                lifecycle.migrate_legacy_crl_sequence(authority, "vpn.example")
        finally:
            lifecycle.remote_crl_sequence = original

    def test_remote_sequence_rejects_ssh_and_unverifiable_metadata(self):
        original = lifecycle.subprocess.run
        try:
            for returncode, output in (
                (1, b""),
                (0, b"not json"),
                (0, json.dumps({"version": 2, "membership_revision": 1, "crl_sequence": "2000", "openvpn_clients": [], "revocations": []}).encode()),
                (0, json.dumps({"version": 2, "membership_revision": 1, "crl_sequence": 2000}).encode()),
            ):
                lifecycle.subprocess.run = lambda *args, returncode=returncode, output=output, **kwargs: type("Result", (), {
                    "returncode": returncode, "stdout": output, "stderr": b"verification failed",
                })()
                with self.assertRaises(lifecycle.Error):
                    lifecycle.remote_crl_sequence("vpn.example")
        finally:
            lifecycle.subprocess.run = original

    def test_unverifiable_remote_sequence_does_not_change_legacy_authority(self):
        authority = self.legacy_authority()
        before = authority["pki"]["crl.pem"], authority["pki"]["crlnumber"]
        original = lifecycle.remote_crl_sequence
        lifecycle.remote_crl_sequence = lambda endpoint: (_ for _ in ()).throw(lifecycle.Error("unverifiable"))
        try:
            with self.assertRaises(lifecycle.Error):
                lifecycle.migrate_legacy_crl_sequence(authority, "vpn.example")
        finally:
            lifecycle.remote_crl_sequence = original
        self.assertEqual((authority["pki"]["crl.pem"], authority["pki"]["crlnumber"]), before)

    def test_migrate_crl_publishes_once_without_membership_mutation(self):
        authority = self.legacy_authority()
        lifecycle.add_open(authority, "revoked")
        lifecycle.revoke_open(authority, "revoked")
        with tempfile.TemporaryDirectory(prefix="bastion-crl-legacy.") as temporary:
            directory = Path(temporary)
            lifecycle.pki_dir(authority, directory)
            lifecycle.run(["openssl", "ca", "-config", str(lifecycle.config(directory)), "-gencrl", "-crldays", "30", "-out", str(directory / "crl.pem")])
            lifecycle.capture_pki(authority, directory)
        membership = authority["membership_revision"]
        server_key = authority["pki"]["server.key"]
        index = authority["pki"]["index.txt"]
        revocations = list(authority["revocations"])
        serial = next(line.split("\t")[3] for line in index.splitlines() if line.startswith("R\t"))
        original = (lifecycle.decrypt, lifecycle.save, lifecycle.vault_password,
                    lifecycle.remote_crl_sequence, lifecycle.publish, sys.argv)
        published = []
        try:
            with tempfile.TemporaryDirectory(prefix="bastion-crl-command.") as temporary:
                ciphertext = Path(temporary) / "authority.json"
                ciphertext.write_text(json.dumps(authority))
                lifecycle.decrypt = lambda path: json.loads(path.read_text())
                lifecycle.save = lambda current, path: path.write_text(json.dumps(current))
                lifecycle.vault_password = lambda: Path(temporary) / "vault-password"
                lifecycle.remote_crl_sequence = lambda endpoint: 0x2000
                lifecycle.publish = lambda current, endpoint: published.append(json.loads(json.dumps(current)))
                sys.argv = ["bastion-vpn-lifecycle", "migrate-crl", "--vpn-host", "vpn.example",
                            "--workdir", temporary, "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 0)
                migrated = json.loads(ciphertext.read_text())
                self.assertEqual(len(published), 1)
                self.assertEqual(migrated["membership_revision"], membership)
                self.assertEqual(migrated["pki"]["server.key"], server_key)
                self.assertEqual(migrated["pki"]["index.txt"], index)
                self.assertEqual(migrated["revocations"], revocations)
                self.assertGreater(lifecycle.crl_sequence(migrated["pki"]["crl.pem"]), 0x2000)
                crl_text = lifecycle.run(["openssl", "crl", "-in", "/dev/stdin", "-noout", "-text"], data=migrated["pki"]["crl.pem"].encode()).decode()
                self.assertIn(serial.upper(), crl_text.replace(":", "").upper())
                lifecycle.remote_crl_sequence = lambda endpoint: (_ for _ in ()).throw(AssertionError("no-op contacted VPS"))
                lifecycle.publish = lambda current, endpoint: (_ for _ in ()).throw(AssertionError("no-op published"))
                self.assertEqual(lifecycle.main(), 0)
                self.assertEqual(json.loads(ciphertext.read_text()), migrated)
        finally:
            (lifecycle.decrypt, lifecycle.save, lifecycle.vault_password,
             lifecycle.remote_crl_sequence, lifecycle.publish, sys.argv) = original


if __name__ == "__main__":
    unittest.main()
