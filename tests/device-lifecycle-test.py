#!/usr/bin/env python3
"""Focused synthetic checks for the owner-side VPN lifecycle manager."""
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_loader("lifecycle", SourceFileLoader("lifecycle", str(ROOT / "scripts/bastion-vpn-lifecycle")))
lifecycle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lifecycle)
REAL_SUBPROCESS_RUN = subprocess.run

# Retained as inert fixture hooks for lifecycle scenarios that predate the
# Vault migration; production now derives all encryption from inventory Vault.
lifecycle.recipient = lambda: "synthetic-owner"
lifecycle.vps_recipient = lambda: "synthetic-vps"


def state():
    return {
        "version": 1, "endpoint": "vpn.example", "revocations": [],
        "pki": {"ca.key": "CA PRIVATE", "ca.crt": "CA PUBLIC", "server.key": "SERVER PRIVATE",
                "server.crt": "SERVER CERT", "crl.pem": "CRL", "index.txt": "", "serial": "1000\n", "crlnumber": "1000\n"},
        "wireguard": {"server_private": "A" * 43 + "=", "server_public": "B" * 43 + "=", "clients": {}},
        "openvpn": {"clients": {}},
    }


def real_age_tools(test: unittest.TestCase) -> tuple[Path, Path]:
    """Find explicit real-age test tools without depending on a VM cache path."""
    def tool(variable: str, fallback: str) -> Path | None:
        value = os.environ.get(variable) or shutil.which(fallback)
        if not value:
            return None
        path = Path(value).expanduser()
        return path if path.is_file() and os.access(path, os.X_OK) else None

    age, keygen = tool("BASTION_AGE_BIN", "age"), tool("BASTION_AGE_KEYGEN", "age-keygen")
    if not age or not keygen:
        test.fail(
            "real-age test setup error: set BASTION_AGE_BIN and BASTION_AGE_KEYGEN "
            "to executable tools, or install age and age-keygen on PATH")
    return age, keygen


def configure_vault_root(root: Path) -> None:
    (root / "inventory").mkdir(parents=True, exist_ok=True)
    password = root / "vault-password"
    password.write_text("synthetic-vault-password\n")
    password.chmod(0o600)
    (root / "inventory/secrets-input.json").write_text(
        json.dumps({"vault_password_file": str(password)}))


class LifecycleTest(unittest.TestCase):
    def setUp(self):
        subprocess.run = REAL_SUBPROCESS_RUN
        self._lifecycle_root = lifecycle.ROOT
        self._temporary_root = tempfile.TemporaryDirectory()
        lifecycle.ROOT = Path(self._temporary_root.name)
        (lifecycle.ROOT / "inventory").mkdir()
        password = lifecycle.ROOT / "vault-password"
        password.write_text("synthetic-vault-password\n")
        password.chmod(0o600)
        (lifecycle.ROOT / "inventory/secrets-input.json").write_text(
            json.dumps({"vault_password_file": str(password)}))

    def tearDown(self):
        # lifecycle imports the same subprocess module as this test module.
        subprocess.run = REAL_SUBPROCESS_RUN
        lifecycle.ROOT = self._lifecycle_root
        self._temporary_root.cleanup()

    def test_make_lifecycle_inputs_are_not_evaluated_by_the_shell(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            marker = root / "shell-executed"
            injection = f'bad"; $$(touch {marker}); #'
            environment = {**os.environ, "XDG_STATE_HOME": str(root / "state")}
            for target, values in (
                ("vpn-add-wg", {"VPN_HOST": "vpn.example", "CLIENT": injection}),
                ("vpn-list-wg", {"VPN_HOST": injection}),
            ):
                result = subprocess.run(
                    ["make", "--no-print-directory", target, *(f"{key}={value}" for key, value in values.items())],
                    cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(marker.exists(), f"{target} evaluated Make input in the shell")
            self.assertFalse((root / "state" / "bastion" / "vpn").exists())

    def test_invalid_input_has_no_subprocess_or_mutation(self):
        calls = []
        original = lifecycle.run
        lifecycle.run = lambda *args, **kwargs: calls.append(args)  # noqa: E731
        try:
            with self.assertRaises(lifecycle.Error):
                lifecycle.name("../unsafe")
            with self.assertRaises(lifecycle.Error):
                lifecycle.host("vpn.example;command")
        finally:
            lifecycle.run = original
        self.assertEqual(calls, [])

    def test_main_rejects_invalid_client_before_initial_issuance(self):
        calls = []
        original_initial = lifecycle.initial
        lifecycle.initial = lambda endpoint: calls.append(endpoint) or state()
        original_argv = sys.argv
        try:
            with tempfile.TemporaryDirectory() as workdir, tempfile.TemporaryDirectory() as state_dir:
                sys.argv = ["bastion-vpn-lifecycle", "add-wg", "--vpn-host", "vpn.example",
                            "--client", "../unsafe", "--workdir", workdir,
                            "--state-file", str(Path(state_dir) / "authority.age")]
                self.assertEqual(lifecycle.main(), 1)
        finally:
            sys.argv = original_argv
            lifecycle.initial = original_initial
        self.assertEqual(calls, [], "invalid input must not trigger initial key issuance")

    def test_main_rejects_invalid_host_before_local_mutation(self):
        calls = []
        original_root, original_initial, original_argv = lifecycle.local_root, lifecycle.initial, sys.argv
        lifecycle.local_root = lambda value: calls.append("root")
        lifecycle.initial = lambda value: calls.append("initial")
        try:
            sys.argv = ["bastion-vpn-lifecycle", "list-wg", "--vpn-host", "bad host"]
            self.assertEqual(lifecycle.main(), 1)
        finally:
            lifecycle.local_root, lifecycle.initial, sys.argv = original_root, original_initial, original_argv
        self.assertEqual(calls, [])

    def test_main_rejects_missing_vault_password_before_initial_issuance(self):
        calls = []
        original_initial, original_password, original_argv = lifecycle.initial, lifecycle.vault_password, sys.argv
        lifecycle.initial = lambda endpoint: calls.append(endpoint) or state()
        lifecycle.vault_password = lambda: (_ for _ in ()).throw(lifecycle.Error("missing Vault password"))
        try:
            with tempfile.TemporaryDirectory() as workdir:
                sys.argv = ["bastion-vpn-lifecycle", "add-wg", "--vpn-host", "vpn.example",
                            "--client", "phone", "--workdir", workdir]
                self.assertEqual(lifecycle.main(), 1)
        finally:
            lifecycle.initial, lifecycle.vault_password, sys.argv = original_initial, original_password, original_argv
        self.assertEqual(calls, [], "invalid Vault configuration must not trigger initial key issuance")

    def test_pending_retry_requires_same_device(self):
        authority = state()
        authority["pending"] = {"action": "add-wg", "device": "phone"}
        original = lifecycle.decrypt, lifecycle.publish, lifecycle.save, lifecycle.recipient, lifecycle.vps_recipient
        published = []
        lifecycle.decrypt = lambda path: authority
        lifecycle.publish = lambda current, endpoint: published.append((current, endpoint))
        lifecycle.save = lambda current, path: None
        lifecycle.recipient, lifecycle.vps_recipient = (lambda: "age1" + "a" * 58), (lambda: "age1" + "b" * 58)
        original_argv = sys.argv
        try:
            with tempfile.TemporaryDirectory() as temporary:
                ciphertext = Path(temporary) / "authority.age"
                ciphertext.write_text("ciphertext")
                sys.argv = ["bastion-vpn-lifecycle", "add-wg", "--vpn-host", "vpn.example",
                            "--client", "laptop", "--workdir", temporary,
                            "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 1)
        finally:
            sys.argv = original_argv
            lifecycle.decrypt, lifecycle.publish, lifecycle.save, lifecycle.recipient, lifecycle.vps_recipient = original
        self.assertEqual(published, [])
        self.assertEqual(authority["pending"], {"action": "add-wg", "device": "phone"})

    def test_recover_fresh_refuses_existing_ciphertext_before_decrypt_or_publish(self):
        calls = []
        original = lifecycle.decrypt, lifecycle.publish, lifecycle.recipient, lifecycle.vps_recipient, sys.argv
        lifecycle.decrypt = lambda path: calls.append("decrypt") or state()
        lifecycle.publish = lambda current, endpoint: calls.append("publish")
        lifecycle.recipient, lifecycle.vps_recipient = (lambda: "age1" + "a" * 58), (lambda: "age1" + "b" * 58)
        try:
            with tempfile.TemporaryDirectory() as temporary:
                ciphertext, replacement = Path(temporary) / "authority.age", Path(temporary) / "replacement.json"
                ciphertext.write_text("stale ciphertext")
                replacement.write_text(json.dumps({"admin-password-hash": "admin", "root-password-hash": "root",
                                                   "ssh-notify-config": "notify"}))
                replacement.chmod(0o600)
                sys.argv = ["bastion-vpn-lifecycle", "recover-fresh", "--vpn-host", "vpn.example",
                            "--replacement-secrets-file", str(replacement), "--workdir", temporary,
                            "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 1)
        finally:
            lifecycle.decrypt, lifecycle.publish, lifecycle.recipient, lifecycle.vps_recipient, sys.argv = original
        self.assertEqual(calls, [])

    def test_recover_fresh_saves_pending_state_then_retries_publish(self):
        authority = state()
        original_migration = lifecycle.migrate_legacy_crl_sequence
        original = (lifecycle.ROOT, lifecycle.initial, lifecycle.stage_vault, lifecycle.publish,
                    lifecycle.save, lifecycle.decrypt, lifecycle.recipient,
                    lifecycle.vps_recipient, sys.argv)
        sops, published = [], []
        try:
            lifecycle.migrate_legacy_crl_sequence = lambda current, endpoint: None
            with tempfile.TemporaryDirectory() as temporary:
                lifecycle.ROOT = Path(temporary)
                configure_vault_root(lifecycle.ROOT)
                lifecycle.initial = lambda endpoint: authority
                def stage(target, values):
                    sops.append((target.name, values.copy()))
                    target.parent.mkdir(exist_ok=True)
                    temporary_path = target.with_name(f".{target.name}.tmp")
                    temporary_path.write_text("ciphertext")
                    return temporary_path
                lifecycle.stage_vault = stage
                lifecycle.publish = lambda current, endpoint: published.append((current, endpoint))
                lifecycle.save = lambda current, path: path.write_text(json.dumps(current))
                lifecycle.decrypt = lambda path: json.loads(path.read_text())
                lifecycle.recipient, lifecycle.vps_recipient = (lambda: "age1" + "a" * 58), (lambda: "age1" + "b" * 58)
                ciphertext = Path(temporary) / "authority.age"
                replacement = Path(temporary) / "replacement.json"
                replacement.write_text(json.dumps({"admin-password-hash": "admin", "root-password-hash": "root",
                                                   "ssh-notify-config": "notify"}))
                replacement.chmod(0o600)
                arguments = ["bastion-vpn-lifecycle", "recover-fresh", "--vpn-host", "vpn.example",
                             "--replacement-secrets-file", str(replacement), "--workdir", temporary,
                             "--state-file", str(ciphertext)]
                sys.argv = arguments
                self.assertEqual(lifecycle.main(), 1)
                self.assertEqual([kind for kind, _ in sops], ["server.yaml", "vpn-server.yaml"])
                self.assertEqual(sops[0][1]["ssh-notify-config"], "notify")
                self.assertEqual(len(published), 1)
                sys.argv = arguments
                self.assertEqual(lifecycle.main(), 0)
                self.assertEqual(len(published), 2)
                self.assertNotIn("pending", lifecycle.decrypt(ciphertext))
                self.assertFalse((Path(temporary) / "recover-fresh.pending").exists())
        finally:
            lifecycle.migrate_legacy_crl_sequence = original_migration
            (lifecycle.ROOT, lifecycle.initial, lifecycle.stage_vault, lifecycle.publish,
             lifecycle.save, lifecycle.decrypt, lifecycle.recipient,
             lifecycle.vps_recipient, sys.argv) = original

    def test_recover_fresh_retries_after_second_sops_write_failure(self):
        authority = state()
        original_migration = lifecycle.migrate_legacy_crl_sequence
        original = (lifecycle.ROOT, lifecycle.initial, lifecycle.stage_vault, lifecycle.publish,
                    lifecycle.save, lifecycle.decrypt, lifecycle.recipient,
                    lifecycle.vps_recipient, sys.argv)
        calls, published, fail_second = [], [], [True]
        try:
            lifecycle.migrate_legacy_crl_sequence = lambda current, endpoint: None
            with tempfile.TemporaryDirectory() as temporary:
                lifecycle.ROOT = Path(temporary)
                configure_vault_root(lifecycle.ROOT)
                lifecycle.initial = lambda endpoint: authority
                def stage(target, values):
                    calls.append(target.name)
                    if target.name == "vpn-server.yaml" and fail_second[0]:
                        raise lifecycle.Error("simulated vpn ciphertext failure")
                    target.parent.mkdir(exist_ok=True)
                    temporary_path = target.with_name(f".{target.name}.tmp")
                    temporary_path.write_text("ciphertext")
                    return temporary_path
                lifecycle.stage_vault = stage
                lifecycle.publish = lambda current, endpoint: published.append((current, endpoint))
                lifecycle.save = lambda current, path: path.write_text(json.dumps(current))
                lifecycle.decrypt = lambda path: json.loads(path.read_text())
                lifecycle.recipient, lifecycle.vps_recipient = (lambda: "age1" + "a" * 58), (lambda: "age1" + "b" * 58)
                ciphertext, replacement = Path(temporary) / "authority.age", Path(temporary) / "replacement.json"
                replacement.write_text(json.dumps({"admin-password-hash": "admin", "root-password-hash": "root",
                                                   "ssh-notify-config": "notify"}))
                replacement.chmod(0o600)
                sys.argv = ["bastion-vpn-lifecycle", "recover-fresh", "--vpn-host", "vpn.example",
                            "--replacement-secrets-file", str(replacement), "--workdir", temporary,
                            "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 1)
                self.assertEqual(calls, ["server.yaml", "vpn-server.yaml"])
                self.assertEqual(published, [])
                self.assertIn("pending", json.loads(ciphertext.read_text()))
                self.assertFalse((lifecycle.ROOT / "secrets/server.yaml").exists())
                self.assertEqual(list((lifecycle.ROOT / "secrets").glob(".*.tmp")), [])
                fail_second[0] = False
                self.assertEqual(lifecycle.main(), 0)
                self.assertEqual(calls, ["server.yaml", "vpn-server.yaml", "server.yaml", "vpn-server.yaml"])
                self.assertEqual(len(published), 1)
                self.assertNotIn("pending", json.loads(ciphertext.read_text()))
        finally:
            lifecycle.migrate_legacy_crl_sequence = original_migration
            (lifecycle.ROOT, lifecycle.initial, lifecycle.stage_vault,
             lifecycle.publish, lifecycle.save, lifecycle.decrypt, lifecycle.recipient,
             lifecycle.vps_recipient, sys.argv) = original

    def test_replacement_secrets_require_exact_protected_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "replacement.json"
            path.write_text(json.dumps({"admin-password-hash": "admin", "root-password-hash": "root",
                                        "ssh-notify-config": "complete config"}))
            with self.assertRaises(lifecycle.Error):
                lifecycle.replacement_secrets(str(path))
            path.chmod(0o600)
            values, digest = lifecycle.replacement_secrets(str(path))
            self.assertEqual(values["ssh-notify-config"], "complete config")
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
            path.write_text(json.dumps({"admin-password-hash": "admin", "root-password-hash": "root"}))
            with self.assertRaises(lifecycle.Error):
                lifecycle.replacement_secrets(str(path))

    def test_recover_compromised_refuses_before_reading_or_preserving_old_ca(self):
        original_root, original_decrypt, original_argv = lifecycle.ROOT, lifecycle.decrypt, sys.argv
        calls = []
        try:
            with tempfile.TemporaryDirectory() as temporary:
                lifecycle.ROOT = Path(temporary)
                configure_vault_root(lifecycle.ROOT)
                ciphertext = Path(temporary) / "authority.yaml"
                ciphertext.write_text(json.dumps(state()))
                replacement = Path(temporary) / "replacement.json"
                replacement.write_text(json.dumps({"admin-password-hash": "admin", "root-password-hash": "root", "ssh-notify-config": "notify"}))
                replacement.chmod(0o600)
                lifecycle.decrypt = lambda path: calls.append(path) or state()
                sys.argv = ["bastion-vpn-lifecycle", "recover-compromised", "--vpn-host", "vpn.example",
                            "--replacement-secrets-file", str(replacement), "--workdir", temporary,
                            "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 1)
        finally:
            lifecycle.ROOT, lifecycle.decrypt, sys.argv = original_root, original_decrypt, original_argv
        self.assertEqual(calls, [])

    def test_replace_server_stages_public_release_before_apply_retry(self):
        authority = state()
        original_migration = lifecycle.migrate_legacy_crl_sequence
        original = (lifecycle.decrypt, lifecycle.save, lifecycle.replace_server,
                    lifecycle.save_server_vault, lifecycle.publish, lifecycle.recipient,
                    lifecycle.vps_recipient, sys.argv)
        staged, sops = [], []
        try:
            lifecycle.migrate_legacy_crl_sequence = lambda current, endpoint: None
            with tempfile.TemporaryDirectory() as temporary:
                ciphertext = Path(temporary) / "authority.age"
                ciphertext.write_text(json.dumps(authority))
                lifecycle.decrypt = lambda path: json.loads(path.read_text())
                lifecycle.save = lambda current, path: path.write_text(json.dumps(current))
                lifecycle.replace_server = lambda current: current["pki"].update({"server.key": "ROTATED", "server.crt": "ROTATED CERT"})
                lifecycle.save_server_vault = lambda current: sops.append(current["pki"]["server.key"])
                def publish(current, endpoint):
                    staged.append((current, endpoint))
                    if len(staged) == 1:
                        raise lifecycle.Error("runtime key has not been applied")
                lifecycle.publish = publish
                lifecycle.recipient, lifecycle.vps_recipient = (lambda: "age1" + "a" * 58), (lambda: "age1" + "b" * 58)
                sys.argv = ["bastion-vpn-lifecycle", "replace-server", "--vpn-host", "vpn.example",
                            "--workdir", temporary, "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 1)
                self.assertEqual(sops, ["ROTATED"])
                self.assertEqual(len(staged), 1)
                self.assertIn("pending", json.loads(ciphertext.read_text()))
                self.assertEqual(lifecycle.main(), 0)
                self.assertEqual(sops, ["ROTATED", "ROTATED"])
                self.assertEqual(len(staged), 2)
                self.assertNotIn("pending", json.loads(ciphertext.read_text()))
        finally:
            lifecycle.migrate_legacy_crl_sequence = original_migration
            (lifecycle.decrypt, lifecycle.save, lifecycle.replace_server,
             lifecycle.save_server_vault, lifecycle.publish, lifecycle.recipient,
             lifecycle.vps_recipient, sys.argv) = original

    def test_replace_server_retries_after_sops_oserror(self):
        authority = state()
        original_migration = lifecycle.migrate_legacy_crl_sequence
        original = (lifecycle.decrypt, lifecycle.save, lifecycle.replace_server,
                    lifecycle.save_server_vault, lifecycle.publish, lifecycle.recipient,
                    lifecycle.vps_recipient, sys.argv)
        failed, published = [True], []
        try:
            lifecycle.migrate_legacy_crl_sequence = lambda current, endpoint: None
            with tempfile.TemporaryDirectory() as temporary:
                ciphertext = Path(temporary) / "authority.age"
                ciphertext.write_text(json.dumps(authority))
                lifecycle.decrypt = lambda path: json.loads(path.read_text())
                lifecycle.save = lambda current, path: path.write_text(json.dumps(current))
                lifecycle.replace_server = lambda current: current["pki"].update({"server.key": "ROTATED", "server.crt": "ROTATED CERT"})
                def save_server(current):
                    if failed[0]:
                        raise OSError("simulated ciphertext replacement failure")
                lifecycle.save_server_vault = save_server
                lifecycle.publish = lambda current, endpoint: published.append((current, endpoint))
                lifecycle.recipient, lifecycle.vps_recipient = (lambda: "age1" + "a" * 58), (lambda: "age1" + "b" * 58)
                sys.argv = ["bastion-vpn-lifecycle", "replace-server", "--vpn-host", "vpn.example",
                            "--workdir", temporary, "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 1)
                self.assertIn("pending", json.loads(ciphertext.read_text()))
                self.assertEqual(published, [])
                failed[0] = False
                self.assertEqual(lifecycle.main(), 0)
                self.assertEqual(len(published), 1)
                self.assertNotIn("pending", json.loads(ciphertext.read_text()))
        finally:
            lifecycle.migrate_legacy_crl_sequence = original_migration
            (lifecycle.decrypt, lifecycle.save, lifecycle.replace_server,
             lifecycle.save_server_vault, lifecycle.publish, lifecycle.recipient,
             lifecycle.vps_recipient, sys.argv) = original

    def test_recover_compromised_refuses_stale_state_before_decrypt_or_publish(self):
        calls = []
        original = lifecycle.decrypt, lifecycle.publish, lifecycle.recipient, lifecycle.vps_recipient, sys.argv
        lifecycle.decrypt = lambda path: calls.append("decrypt") or state()
        lifecycle.publish = lambda current, endpoint: calls.append("publish")
        lifecycle.recipient, lifecycle.vps_recipient = (lambda: "age1" + "a" * 58), (lambda: "age1" + "b" * 58)
        try:
            with tempfile.TemporaryDirectory() as temporary:
                ciphertext, replacement = Path(temporary) / "authority.age", Path(temporary) / "replacement.json"
                ciphertext.write_text(json.dumps(state()))
                replacement.write_text(json.dumps({"admin-password-hash": "admin", "root-password-hash": "root",
                                                   "ssh-notify-config": "notify"}))
                replacement.chmod(0o600)
                sys.argv = ["bastion-vpn-lifecycle", "recover-compromised", "--vpn-host", "vpn.example",
                            "--replacement-secrets-file", str(replacement), "--workdir", temporary,
                            "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 1)
        finally:
            lifecycle.decrypt, lifecycle.publish, lifecycle.recipient, lifecycle.vps_recipient, sys.argv = original
        self.assertEqual(calls, [])

    def test_recover_compromised_refuses_older_git_ciphertext_after_current_marker(self):
        calls = []
        original = lifecycle.decrypt, lifecycle.publish, lifecycle.recipient, lifecycle.vps_recipient, sys.argv
        lifecycle.decrypt = lambda path: calls.append("decrypt") or state()
        lifecycle.publish = lambda current, endpoint: calls.append("publish")
        lifecycle.recipient, lifecycle.vps_recipient = (lambda: "age1" + "a" * 58), (lambda: "age1" + "b" * 58)
        try:
            with tempfile.TemporaryDirectory() as temporary:
                ciphertext, replacement = Path(temporary) / "authority.age", Path(temporary) / "replacement.json"
                ciphertext.write_text("newer current ciphertext")
                lifecycle.save_current_authority(Path(temporary), ciphertext)
                ciphertext.write_text("older Git ciphertext")
                replacement.write_text(json.dumps({"admin-password-hash": "admin", "root-password-hash": "root",
                                                   "ssh-notify-config": "notify"}))
                replacement.chmod(0o600)
                sys.argv = ["bastion-vpn-lifecycle", "recover-compromised", "--vpn-host", "vpn.example",
                            "--replacement-secrets-file", str(replacement), "--workdir", temporary,
                            "--state-file", str(ciphertext)]
                self.assertEqual(lifecycle.main(), 1)
        finally:
            lifecycle.decrypt, lifecycle.publish, lifecycle.recipient, lifecycle.vps_recipient, sys.argv = original
        self.assertEqual(calls, [])

    def test_duplicate_wireguard_add_preserves_existing_key(self):
        authority = state()
        existing = {"private": "C" * 43 + "=", "public": "D" * 43 + "=",
                    "ipv4": "10.43.0.2", "ipv6": "fd42:2::2"}
        authority["wireguard"]["clients"]["phone"] = existing.copy()
        original = lifecycle.wg_pair
        lifecycle.wg_pair = lambda: (_ for _ in ()).throw(AssertionError("key regenerated"))
        try:
            with self.assertRaises(lifecycle.Error):
                lifecycle.add_wg(authority, "phone")
        finally:
            lifecycle.wg_pair = original
        self.assertEqual(authority["wireguard"]["clients"]["phone"], existing)

    def test_public_release_excludes_private_authority_material(self):
        authority = state()
        authority["wireguard"]["clients"]["phone"] = {"private": "C" * 43 + "=", "public": "D" * 43 + "=", "ipv4": "10.43.0.2", "ipv6": "fd42:2::2"}
        original = lifecycle.crl_sequence
        lifecycle.crl_sequence = lambda contents: 4096
        try:
            with tempfile.TemporaryDirectory() as temporary:
                release = Path(temporary) / "release"
                lifecycle.release(authority, release)
                self.assertEqual(sorted(str(path.relative_to(release)) for path in release.rglob("*") if path.is_file()), ["READY", "manifest.sha256", "openvpn/ca.crt", "openvpn/crl.pem", "openvpn/index.txt", "openvpn/metadata.json", "openvpn/server.crt", "wireguard/peers"])
                self.assertNotIn("PRIVATE", "".join(path.read_text() for path in release.rglob("*") if path.is_file()))
        finally:
            lifecycle.crl_sequence = original

    def test_wireguard_profile_is_private_and_full_tunnel(self):
        authority = state()
        authority["wireguard"]["clients"]["phone"] = {"private": "C" * 43 + "=", "public": "D" * 43 + "=", "ipv4": "10.43.0.2", "ipv6": "fd42:2::2"}
        with tempfile.TemporaryDirectory() as temporary:
            path = lifecycle.export_wg(authority, Path(temporary), "phone")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            text = path.read_text()
            self.assertIn("AllowedIPs = 0.0.0.0/0, ::/0", text)
            self.assertIn("DNS = 1.1.1.1, 8.8.8.8", text)

    def test_openvpn_export_fails_without_current_server_certificate(self):
        authority = state()
        authority["openvpn"]["clients"]["laptop"] = {"private": "CLIENT PRIVATE", "cert": "CLIENT CERT"}
        authority["pki"]["server.crt"] = ""
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(lifecycle.Error):
                lifecycle.export_open(authority, Path(temporary), "laptop")
            self.assertFalse((Path(temporary) / "profiles" / "laptop.ovpn").exists())

    def test_openvpn_export_requires_local_private_key_without_touching_authority(self):
        authority = state()
        authority["openvpn"]["clients"]["laptop"] = {"private": "", "cert": "CLIENT CERT"}
        before = json.dumps(authority, sort_keys=True)
        calls = []
        original_run = lifecycle.run
        lifecycle.run = lambda *args, **kwargs: calls.append(args)  # noqa: E731
        try:
            with tempfile.TemporaryDirectory() as temporary:
                profile = Path(temporary) / "profiles" / "laptop.ovpn"
                with self.assertRaises(lifecycle.Error):
                    lifecycle.export_open(authority, Path(temporary), "laptop")
                self.assertFalse(profile.exists())
        finally:
            lifecycle.run = original_run
        self.assertEqual(calls, [])
        self.assertEqual(json.dumps(authority, sort_keys=True), before)

    def test_openvpn_export_replaces_pin_from_current_identity_locally(self):
        authority = state()
        authority["openvpn"]["clients"]["laptop"] = {"private": "CLIENT PRIVATE", "cert": "CLIENT CERT"}
        authority["pki"]["server.crt"] = "SERVER CERTIFICATE ONE"
        first, second = ":".join(["A1"] * 32), ":".join(["B2"] * 32)
        fingerprints, commands = [first, second], []
        original_run = lifecycle.run

        def fingerprint(command, data=None):
            commands.append(command)
            self.assertEqual(command[:2], ["openssl", "x509"])
            return f"sha256 Fingerprint={fingerprints.pop(0)}\n".encode()

        lifecycle.run = fingerprint
        try:
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                before_first_export = json.dumps(authority, sort_keys=True)
                profile = lifecycle.export_open(authority, root, "laptop")
                self.assertEqual(stat.S_IMODE(profile.stat().st_mode), 0o600)
                self.assertIn(f"peer-fingerprint {first}", profile.read_text())
                self.assertEqual(json.dumps(authority, sort_keys=True), before_first_export)

                authority["endpoint"] = "replacement.example"
                authority["pki"]["server.crt"] = "SERVER CERTIFICATE TWO"
                before_second_export = json.dumps(authority, sort_keys=True)
                profile = lifecycle.export_open(authority, root, "laptop")
                contents = profile.read_text()
                self.assertIn("remote replacement.example 443", contents)
                self.assertIn("redirect-gateway def1 ipv6", contents)
                self.assertIn("dhcp-option DNS 1.1.1.1", contents)
                self.assertIn("dhcp-option DNS 8.8.8.8", contents)
                self.assertEqual(re.findall(r"^peer-fingerprint .+$", contents, re.MULTILINE), [f"peer-fingerprint {second}"])
                self.assertNotIn(first, contents)
                self.assertEqual(stat.S_IMODE(profile.stat().st_mode), 0o600)
                self.assertEqual(json.dumps(authority, sort_keys=True), before_second_export)
        finally:
            lifecycle.run = original_run
        self.assertEqual(len(commands), 2)
        self.assertTrue(all(command[0] == "openssl" for command in commands))
        self.assertNotIn("ssh", " ".join(" ".join(command) for command in commands))

    def test_deleting_local_profile_does_not_revoke_wireguard_device(self):
        authority = state()
        authority["wireguard"]["clients"]["phone"] = {"private": "C" * 43 + "=", "public": "D" * 43 + "=", "ipv4": "10.43.0.2", "ipv6": "fd42:2::2"}
        with tempfile.TemporaryDirectory() as temporary:
            profile = lifecycle.export_wg(authority, Path(temporary), "phone")
            profile.unlink()
            self.assertFalse(profile.exists())
        self.assertEqual(authority["revocations"], [])
        self.assertIn("phone", authority["wireguard"]["clients"])

    def test_atomic_vault_save_uses_temporary_ciphertext(self):
        authority = state()
        original_run, original_recipient = lifecycle.run, lifecycle.recipient
        lifecycle.recipient = lambda: "age1" + "a" * 58
        def fake_run(command, data=None, **kwargs):
            self.assertEqual(command[:2], ["ansible-vault", "encrypt"])
            Path(command[command.index("--output") + 1]).write_bytes(b"$ANSIBLE_VAULT;1.1;AES256\n")
            return b""
        lifecycle.run = fake_run
        try:
            with tempfile.TemporaryDirectory() as temporary:
                target = Path(temporary) / "vpn-authority.yaml"
                lifecycle.save(authority, target)
                self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
                self.assertTrue(target.read_text().startswith("$ANSIBLE_VAULT;1.1;AES256"))
                self.assertEqual(list(Path(temporary).glob(".*.tmp")), [])
        finally:
            lifecycle.run, lifecycle.recipient = original_run, original_recipient

    def test_vault_encrypt_uses_password_file_without_plaintext_arguments(self):
        commands = []
        original_run = lifecycle.run
        lifecycle.run = lambda command, data=None, **kwargs: commands.append(command) or b""
        try:
            with tempfile.TemporaryDirectory() as temporary:
                target = Path(temporary) / "authority.yaml"
                with self.assertRaises(Exception):
                    lifecycle.stage_vault(target, state())
        finally:
            lifecycle.run = original_run
        self.assertEqual(commands[0][0:2], ["ansible-vault", "encrypt"])
        self.assertNotIn("CA PRIVATE", " ".join(commands[0]))

    def test_authority_lock_blocks_competing_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            entered, complete = threading.Event(), threading.Event()
            def contender():
                with lifecycle.lock(Path(temporary)):
                    entered.set()
                complete.set()
            with lifecycle.lock(Path(temporary)):
                thread = threading.Thread(target=contender)
                thread.start()
                time.sleep(0.03)
                self.assertFalse(entered.is_set())
            thread.join(1)
            self.assertTrue(entered.is_set() and complete.is_set())

    def test_persisted_transaction_retries_add_and_revoke_without_lost_update(self):
        authority = state()
        original_migration = lifecycle.migrate_legacy_crl_sequence
        original = lifecycle.decrypt, lifecycle.save, lifecycle.publish, lifecycle.wg_pair, lifecycle.recipient, lifecycle.vps_recipient, sys.argv
        failures, server = [True, False, True, False], set()
        lifecycle.decrypt = lambda path: json.loads(path.read_text())
        lifecycle.save = lambda current, path: path.write_text(json.dumps(current))
        lifecycle.wg_pair = lambda: ("C" * 43 + "=", "D" * 43 + "=")
        lifecycle.recipient, lifecycle.vps_recipient = (lambda: "age1" + "a" * 58), (lambda: "age1" + "b" * 58)
        def publish(current, endpoint):
            if failures.pop(0):
                raise lifecycle.Error("simulated remote verification failure")
            server.clear(); server.update(record["public"] for record in current["wireguard"]["clients"].values())
        lifecycle.publish = publish
        lifecycle.migrate_legacy_crl_sequence = lambda current, endpoint: None
        import builtins
        original_input = builtins.input
        try:
            with tempfile.TemporaryDirectory() as temporary:
                ciphertext = Path(temporary) / "synthetic-ciphertext"
                ciphertext.write_text(json.dumps(authority))
                def invoke(*arguments):
                    sys.argv = ["bastion-vpn-lifecycle", *arguments, "--vpn-host", "vpn.example", "--workdir", temporary, "--state-file", str(ciphertext)]
                    return lifecycle.main()
                self.assertEqual(invoke("add-wg", "--client", "phone"), 1)
                self.assertEqual(json.loads(ciphertext.read_text())["pending"]["device"], "phone")
                self.assertTrue(lifecycle.current_authority(Path(temporary), ciphertext))
                self.assertEqual(invoke("add-wg", "--client", "phone"), 0)
                self.assertEqual(server, {"D" * 43 + "="})
                builtins.input = lambda prompt: "phone"
                self.assertEqual(invoke("revoke-wg"), 1)
                self.assertEqual(invoke("revoke-wg"), 0)
                converged = json.loads(ciphertext.read_text())
                self.assertNotIn("pending", converged)
                self.assertEqual(converged["wireguard"]["clients"], {})
                self.assertEqual(server, set())
        finally:
            lifecycle.migrate_legacy_crl_sequence = original_migration
            lifecycle.decrypt, lifecycle.save, lifecycle.publish, lifecycle.wg_pair, lifecycle.recipient, lifecycle.vps_recipient, sys.argv = original
            builtins.input = original_input

    def test_server_vault_contains_only_server_keys(self):
        authority = state()
        original_root, original_run = lifecycle.ROOT, lifecycle.run
        original_recipient, original_vps = lifecycle.recipient, lifecycle.vps_recipient
        commands = []
        lifecycle.recipient = lambda: "age1" + "a" * 58
        lifecycle.vps_recipient = lambda: "age1" + "b" * 58
        def fake_run(command, data=None, **kwargs):
            commands.append((command, data))
            output = Path(command[command.index("--output") + 1])
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(b"$ANSIBLE_VAULT;1.1;AES256\n")
            return b""
        lifecycle.run = fake_run
        try:
            with tempfile.TemporaryDirectory() as temporary:
                lifecycle.ROOT = Path(temporary)
                configure_vault_root(lifecycle.ROOT)
                lifecycle.save_server_vault(authority)
                target = Path(temporary) / "secrets/vpn-server.yaml"
                self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
                self.assertEqual(len(commands), 1)
                command, payload = commands[0]
                self.assertIn("ansible-vault", command)
                self.assertNotIn("SERVER PRIVATE", " ".join(command))
                self.assertIn("--vault-password-file", command)
        finally:
            lifecycle.ROOT, lifecycle.run = original_root, original_run
            lifecycle.recipient, lifecycle.vps_recipient = original_recipient, original_vps

    def test_interactive_cancellation_never_selects_a_device(self):
        authority = state()
        authority["wireguard"]["clients"]["phone"] = {"private": "C" * 43 + "=", "public": "D" * 43 + "=", "ipv4": "10.43.0.2", "ipv6": "fd42:2::2"}
        import builtins
        original = builtins.input
        try:
            for response in ("", "unknown"):
                builtins.input = lambda prompt, value=response: value
                with self.assertRaises(lifecycle.Error):
                    lifecycle.chosen(authority, "wg")
            builtins.input = lambda prompt: (_ for _ in ()).throw(EOFError())
            with self.assertRaises(lifecycle.Error):
                lifecycle.chosen(authority, "wg")
        finally:
            builtins.input = original
        self.assertIn("phone", authority["wireguard"]["clients"])

    def test_publish_runs_su_over_an_inherited_terminal(self):
        authority = state()
        original_run, original_interactive, original_subprocess, original_sequence = lifecycle.run, lifecycle.interactive, lifecycle.subprocess.run, lifecycle.crl_sequence
        copied, interactive = [], []
        lifecycle.run = lambda command, data=None: copied.append(command) or b""
        lifecycle.interactive = lambda command: interactive.append(command)
        lifecycle.subprocess.run = lambda *args, **kwargs: type("Result", (), {"returncode": 0})()
        lifecycle.crl_sequence = lambda contents: 4096
        try:
            lifecycle.publish(authority, "vpn.example")
        finally:
            lifecycle.run, lifecycle.interactive, lifecycle.subprocess.run, lifecycle.crl_sequence = original_run, original_interactive, original_subprocess, original_sequence
        self.assertEqual(len(interactive), 1)
        command = interactive[0]
        self.assertEqual(command[0:2], ["ssh", "-tt"])
        self.assertIn("su -c", command[-1])
        self.assertNotIn("SERVER PRIVATE", " ".join(command))
        self.assertEqual(copied[0][0], "scp")

    def test_root_publisher_releases_lock_and_retries_failed_live_check(self):
        public_key = "D" * 43 + "="
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            state_root, active, fake_bin = temporary / "state", temporary / "active", temporary / "bin"
            (state_root / "releases").mkdir(parents=True)
            fake_bin.mkdir()
            apply = temporary / "apply"
            apply.write_text(f"#!/usr/bin/env bash\nexec 9>{temporary / 'state.lock'}\ntimeout 1 flock -s 9\nmkdir -p \"$ACTIVE/openvpn\"\nprintf crl > \"$ACTIVE/openvpn/crl.pem\"\n")
            wg = fake_bin / "wg"
            wg.write_text(f"#!/usr/bin/env bash\ntest \"${{WG_MODE:-good}}\" = good && printf '%s\\n' {public_key}\n")
            systemctl = fake_bin / "systemctl"
            systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
            for path in (apply, wg, systemctl): path.chmod(0o700)
            source = (ROOT / "roles/vpn/files/bastion-vpn-publish-state").read_text()
            source = source.replace("/var/lib/bastion/vpn", str(state_root)).replace("/run/lock/bastion-vpn-state.lock", str(temporary / "state.lock"))
            source = source.replace(" /run/lock", f" {temporary}")
            source = source.replace("/home/admin/.bastion-vpn-release-", str(temporary / ".bastion-vpn-release-"))
            source = source.replace("/usr/local/libexec/bastion-vpn-apply-state", str(apply)).replace("/run/bastion-vpn/active", str(active))
            source = source.replace("/usr/local/libexec/bastion-vpn-verify-state", f"readlink -f {state_root}/current")
            source = source.replace('chown -R root:root "$release"', ':')
            publisher = temporary / "publisher"; publisher.write_text(source); publisher.chmod(0o700)
            release = temporary / "release"
            (release / "openvpn").mkdir(parents=True); (release / "wireguard").mkdir()
            for path in ("ca.crt", "crl.pem", "index.txt", "server.crt"):
                (release / "openvpn" / path).write_text("public\n")
            (release / "openvpn/metadata.json").write_text(json.dumps({"version": 2, "membership_revision": 1, "crl_sequence": 4096, "openvpn_clients": [], "revocations": []}) + "\n")
            (release / "wireguard/peers").write_text(f"{public_key} 10.43.0.2 fd42:2::2\n")
            (release / "manifest.sha256").write_text("manifest\n"); (release / "READY").write_text("bastion-vpn-state-v1\n")
            archive = temporary / ".bastion-vpn-release-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.tar"
            subprocess.run(["tar", "-cf", str(archive), "-C", str(temporary), "release"], check=True)
            environment = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}", "ACTIVE": str(active)}
            self.assertEqual(subprocess.run([str(publisher), str(archive)], env=environment).returncode, 0)
            archive.write_bytes(b"")
            subprocess.run(["tar", "-cf", str(archive), "-C", str(temporary), "release"], check=True)
            self.assertNotEqual(subprocess.run([str(publisher), str(archive)], env={**environment, "WG_MODE": "bad"}).returncode, 0)
            archive.write_bytes(b"")
            subprocess.run(["tar", "-cf", str(archive), "-C", str(temporary), "release"], check=True)
            self.assertEqual(subprocess.run([str(publisher), str(archive)], env=environment).returncode, 0)


if __name__ == "__main__":
    unittest.main()
