#!/usr/bin/env python3
"""Focused regressions for the local current-authority marker."""
import builtins
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_loader(
    "authority_marker_lifecycle", SourceFileLoader(
        "authority_marker_lifecycle", str(ROOT / "scripts/bastion-vpn-lifecycle")))
lifecycle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lifecycle)


def state():
    return {
        "version": 1,
        "endpoint": "vpn.example",
        "revocations": [],
        "pki": {
            "ca.key": "CA PRIVATE", "ca.crt": "CA PUBLIC", "server.key": "SERVER PRIVATE",
            "server.crt": "SERVER CERT", "crl.pem": "CRL", "index.txt": "",
            "serial": "1000\n", "crlnumber": "1000\n",
        },
        "wireguard": {
            "server_private": "A" * 43 + "=", "server_public": "B" * 43 + "=", "clients": {},
        },
        "openvpn": {"clients": {}},
    }


class AuthorityMarkerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.original_root, self.original_argv = lifecycle.ROOT, sys.argv
        lifecycle.ROOT = self.root
        (self.root / "inventory").mkdir()
        password = self.root / "vault-password"
        password.write_text("synthetic-vault-password\n")
        password.chmod(0o600)
        (self.root / "inventory/secrets-input.json").write_text(
            json.dumps({"vault_password_file": str(password)}))
        self.ciphertext = self.root / "authority.yaml"

    def tearDown(self):
        lifecycle.ROOT, sys.argv = self.original_root, self.original_argv
        self.temporary.cleanup()

    def invoke(self, *arguments):
        sys.argv = ["bastion-vpn-lifecycle", *arguments, "--vpn-host", "vpn.example",
                    "--workdir", str(self.root), "--state-file", str(self.ciphertext)]
        return lifecycle.main()

    def patch_transaction(self, published=None):
        original = lifecycle.decrypt, lifecycle.save, lifecycle.publish, lifecycle.wg_pair
        lifecycle.decrypt = lambda path: json.loads(path.read_text())
        lifecycle.save = lambda current, path: path.write_text(json.dumps(current))
        lifecycle.publish = published or (lambda current, endpoint: None)
        lifecycle.wg_pair = lambda: ("C" * 43 + "=", "D" * 43 + "=")
        return original

    def restore_transaction(self, original):
        lifecycle.decrypt, lifecycle.save, lifecycle.publish, lifecycle.wg_pair = original

    def test_successful_add_and_revoke_refresh_the_final_marker(self):
        self.ciphertext.write_text(json.dumps(state()))
        original = self.patch_transaction()
        original_input = builtins.input
        try:
            self.assertEqual(self.invoke("add-wg", "--client", "phone"), 0)
            self.assertTrue(lifecycle.current_authority(self.root, self.ciphertext))
            self.assertNotIn("pending", json.loads(self.ciphertext.read_text()))

            builtins.input = lambda prompt: "phone"
            self.assertEqual(self.invoke("revoke-wg"), 0)
            current = json.loads(self.ciphertext.read_text())
            self.assertTrue(lifecycle.current_authority(self.root, self.ciphertext))
            self.assertNotIn("pending", current)
            self.assertEqual(current["wireguard"]["clients"], {})
        finally:
            builtins.input = original_input
            self.restore_transaction(original)

    def test_partial_publication_keeps_the_pending_state_current(self):
        self.ciphertext.write_text(json.dumps(state()))
        original = self.patch_transaction(
            lambda current, endpoint: (_ for _ in ()).throw(lifecycle.Error("synthetic publish failure")))
        try:
            self.assertEqual(self.invoke("add-wg", "--client", "phone"), 1)
        finally:
            self.restore_transaction(original)
        current = json.loads(self.ciphertext.read_text())
        self.assertEqual(current["pending"]["device"], "phone")
        self.assertTrue(lifecycle.current_authority(self.root, self.ciphertext))

    def test_current_marker_does_not_allow_ca_preserving_compromise_recovery(self):
        self.ciphertext.write_text(json.dumps(state()))
        original = self.patch_transaction()
        replacement = self.root / "replacement.json"
        replacement.write_text(json.dumps({
            "admin-password-hash": "admin", "root-password-hash": "root", "ssh-notify-config": "notify"}))
        replacement.chmod(0o600)
        try:
            self.assertEqual(self.invoke("add-wg", "--client", "phone"), 0)
            self.assertEqual(self.invoke("recover-compromised", "--replacement-secrets-file", str(replacement)), 1)
        finally:
            self.restore_transaction(original)
        self.assertTrue(lifecycle.current_authority(self.root, self.ciphertext))
        self.assertNotIn("pending", json.loads(self.ciphertext.read_text()))

    def test_stale_ciphertext_is_rejected_before_recovery_decrypts_it(self):
        self.ciphertext.write_text("current ciphertext")
        lifecycle.save_current_authority(self.root, self.ciphertext)
        self.ciphertext.write_text("stale ciphertext")
        replacement = self.root / "replacement.json"
        replacement.write_text(json.dumps({
            "admin-password-hash": "admin", "root-password-hash": "root", "ssh-notify-config": "notify"}))
        replacement.chmod(0o600)
        calls, original_decrypt = [], lifecycle.decrypt
        lifecycle.decrypt = lambda path: calls.append(path) or state()
        try:
            self.assertEqual(self.invoke("recover-compromised", "--replacement-secrets-file", str(replacement)), 1)
        finally:
            lifecycle.decrypt = original_decrypt
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
