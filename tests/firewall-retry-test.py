#!/usr/bin/env python3
"""Regression checks for the durable UFW apply marker ordering."""

import base64
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


TASKS = Path(__file__).parents[1] / "roles/firewall/tasks/main.yml"
SOURCE = TASKS.read_text()
ROOT = TASKS.parents[3]
ANSIBLE = ROOT / ".venv/bin/ansible-playbook"
POLICY_FILES = (
    "/etc/default/ufw", "/etc/ufw/ufw.conf", "/etc/ufw/sysctl.conf",
    "/etc/ufw/before.rules", "/etc/ufw/before6.rules", "/etc/ufw/after.rules",
    "/etc/ufw/after6.rules", "/etc/ufw/before.init", "/etc/ufw/after.init",
)
CONFFILES = ("/etc/default/ufw", "/etc/ufw/sysctl.conf")
SKELETON_PATHS = {
    "/etc/ufw/ufw.conf": "/usr/share/ufw/ufw.conf",
    "/etc/ufw/before.rules": "/usr/share/ufw/before.rules",
    "/etc/ufw/before6.rules": "/usr/share/ufw/before6.rules",
    "/etc/ufw/after.rules": "/usr/share/ufw/after.rules",
    "/etc/ufw/after6.rules": "/usr/share/ufw/after6.rules",
    "/etc/ufw/before.init": "/usr/share/ufw/before.init",
    "/etc/ufw/after.init": "/usr/share/ufw/after.init",
}
DEFAULTS = (
    "IPV6=yes", "DEFAULT_INPUT_POLICY=\"DROP\"", "DEFAULT_OUTPUT_POLICY=\"ACCEPT\"",
    "DEFAULT_FORWARD_POLICY=\"DROP\"", "DEFAULT_APPLICATION_POLICY=\"SKIP\"",
    "MANAGE_BUILTINS=no", "IPT_SYSCTL=/etc/ufw/sysctl.conf", 'IPT_MODULES=""',
)


def position(name: str) -> int:
    marker = f"- name: {name}"
    found = SOURCE.find(marker)
    if found < 0:
        raise AssertionError(f"missing {marker}")
    return found


def quoted(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def guard_tasks() -> str:
    start = SOURCE.index("- name: Start with no safe interrupted UFW apply")
    end = SOURCE.index("- name: Reject unexpected UFW policy before mutation", start)
    return SOURCE[start:end]


def raw_user_rule_task() -> str:
    start = SOURCE.index("- name: Read existing raw UFW user-chain rules")
    end = SOURCE.index("- name: Read fresh UFW default policies", start)
    return SOURCE[start:end]


def template_checksum(name: str) -> str:
    rendered = (ROOT / "roles/firewall/templates" / name).read_text().replace(
        "{{ netplan_interface }}", "ens4"
    )
    return hashlib.md5(rendered.encode()).hexdigest()


def run_guard(*, targets: tuple[str, ...] = (), raw: str = "", added: str = "") -> int:
    package_hashes = {path: f"a{index:031x}" for index, path in enumerate(POLICY_FILES, 1)}
    hashes = package_hashes.copy()
    if "/etc/ufw/before.rules" in targets:
        hashes["/etc/ufw/before.rules"] = template_checksum("before.rules.j2")
    if "/etc/ufw/before6.rules" in targets:
        hashes["/etc/ufw/before6.rules"] = template_checksum("before6.rules.j2")
    if "custom-after" in targets:
        hashes["/etc/ufw/after.rules"] = "f" * 32
    conffiles = "\n".join(f"        {path} {package_hashes[path]}" for path in CONFFILES)
    skeletons = "\n".join(
        f"        - {package_hashes[path]}  {skeleton}" for path, skeleton in SKELETON_PATHS.items()
    )
    results = "\n".join(
        f"      - item: {path}\n        stat: {{exists: true, checksum: {hashes[path]}}}"
        for path in POLICY_FILES
    )
    conf = "ENABLED=no\nLOGLEVEL=low\n"
    play = f"""---
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    netplan_interface: ens4
    firewall_ufw_pending: {{stat: {{exists: true}}}}
    firewall_ufw_pending_contents:
      stdout_lines: [bastion-ufw-apply-v1, {hashlib.sha256(conf.replace('ENABLED=no', '').encode()).hexdigest()}]
    firewall_ufw_conf: {{content: {base64.b64encode(conf.encode()).decode()}}}
    firewall_ufw_package_conffiles:
      stdout: |
{conffiles}
      stdout_lines:
{chr(10).join('        - ' + quoted(' ' + path + ' ' + package_hashes[path]) for path in CONFFILES)}
    firewall_ufw_package_skeletons:
      stdout_lines:
{skeletons}
    firewall_ufw_policy_inputs:
      results:
{results}
    firewall_ufw_defaults:
      stdout_lines: {list(DEFAULTS)}
    firewall_ufw_status: {{stdout: 'Status: inactive'}}
    firewall_ufw_added_rules:
      stdout_lines: [{quoted('Added user rules (see \'ufw status numbered\'):')}, {quoted(added)}]
    firewall_ufw_raw_user_rules:
      stdout_lines: [{quoted(raw)}]
    firewall_ufw_enabled_setting: {{stdout: ENABLED=no}}
  tasks:
    {guard_tasks().replace(chr(10), chr(10) + '    ').rstrip()}
"""
    with tempfile.TemporaryDirectory(prefix="bastion-ufw-retry-") as directory:
        temp = Path(directory)
        shutil.copytree(ROOT / "roles/firewall/templates", temp / "templates")
        (temp / "play.yml").write_text(play)
        env = os.environ | {"ANSIBLE_LOCAL_TEMP": str(temp / "local"), "ANSIBLE_HOME": str(temp / "home")}
        return subprocess.run([str(ANSIBLE), "-i", "localhost,", str(temp / "play.yml")], cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT).returncode


def run_raw_user_rule_task(*, extra: str = "", expected_rc: int) -> int:
    fixtures = ROOT / "tests/fixtures/ufw"
    with tempfile.TemporaryDirectory(prefix="bastion-ufw-raw-") as directory:
        temp = Path(directory)
        user_rules = temp / "user.rules"
        user6_rules = temp / "user6.rules"
        user_rules.write_text((fixtures / "user.rules").read_text() + extra)
        user6_rules.write_text((fixtures / "user6.rules").read_text())
        task = raw_user_rule_task().replace("/etc/ufw/user.rules", str(user_rules)).replace(
            "/etc/ufw/user6.rules", str(user6_rules)
        )
        play = f"""---
- hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    {task.replace(chr(10), chr(10) + '    ').rstrip()}
    - ansible.builtin.assert:
        that:
          - firewall_ufw_raw_user_rules.rc == {expected_rc}
          - firewall_ufw_raw_user_rules.stdout == {'""' if expected_rc == 1 else quoted(extra.rstrip())}
"""
        (temp / "play.yml").write_text(play)
        env = os.environ | {"ANSIBLE_LOCAL_TEMP": str(temp / "local"), "ANSIBLE_HOME": str(temp / "home")}
        return subprocess.run([str(ANSIBLE), "-i", "localhost,", str(temp / "play.yml")], cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT).returncode


class FirewallRetryTest(unittest.TestCase):
    def test_pending_marker_covers_every_mutation_and_final_commit(self):
        pending = position("Record the Bastion UFW apply in progress")
        mutations = (
            "Preserve fail2ban built-in chains",
            "Enable IPv6 in UFW",
            "Install Bastion UFW IPv4 rules",
            "Install Bastion UFW IPv6 rules",
            "Allow SSH through UFW",
            "Enable the Bastion UFW policy",
        )
        manifest = position("Record the managed UFW state manifest")
        version = position("Record the managed UFW state version")
        clear = position("Clear the completed Bastion UFW apply marker")

        self.assertIn("bastion-ufw-apply-v1", SOURCE)
        self.assertTrue(all(pending < position(name) for name in mutations))
        self.assertLess(position("Require the active UFW policy"), manifest)
        self.assertLess(manifest, version)
        self.assertLess(version, clear)

    def test_each_injected_interruption_leaves_the_marker_for_retry(self):
        pending = position("Record the Bastion UFW apply in progress")
        clear = position("Clear the completed Bastion UFW apply marker")
        failure_points = (
            "Install Bastion UFW IPv4 rules",
            "Install Bastion UFW IPv6 rules",
            "Allow SSH through UFW",
            "Record the managed UFW state manifest",
            "Record the managed UFW state version",
        )

        for name in failure_points:
            with self.subTest(name=name):
                self.assertLess(pending, position(name))
                self.assertLess(position(name), clear)

    def test_resume_guard_binds_the_marker_to_unchanged_ufw_configuration(self):
        self.assertIn("Validate safe interrupted UFW policy inputs", SOURCE)
        self.assertIn("firewall_ufw_pending_contents.stdout_lines | length == 2", SOURCE)
        self.assertIn("regex_replace('(?m)^ENABLED=(yes|no)$', '') | hash('sha256')", SOURCE)
        self.assertIn("firewall_ufw_pending_raw_rule", SOURCE)

    def test_captured_ubuntu_user_rule_scaffolds_are_fresh(self):
        if not ANSIBLE.is_file():
            self.skipTest("missing project Ansible virtual environment")
        self.assertEqual(run_raw_user_rule_task(expected_rc=1), 0)

    def test_raw_user_rule_task_rejects_custom_rules_and_tables(self):
        if not ANSIBLE.is_file():
            self.skipTest("missing project Ansible virtual environment")
        for extra in (
            "-A ufw-user-input -p tcp --dport 80 -j ACCEPT\n",
            "-A ufw-logging-allow -j ACCEPT\n",
            "*nat\n",
        ):
            with self.subTest(extra=extra):
                self.assertEqual(run_raw_user_rule_task(extra=extra, expected_rc=0), 0)

    def test_guard_accepts_each_safe_interrupted_write(self):
        if not ANSIBLE.is_file():
            self.skipTest("missing project Ansible virtual environment")
        for targets, raw, added in (
            ((), "", ""),
            (("/etc/ufw/before.rules",), "", ""),
            (("/etc/ufw/before.rules", "/etc/ufw/before6.rules"), "", ""),
            (("/etc/ufw/before.rules",), "-A ufw-user-input -p tcp --dport 22 -j ACCEPT", "ufw allow 22/tcp"),
            (("/etc/ufw/before6.rules",), "-A ufw6-user-input -p tcp --dport 22 -j ACCEPT", "ufw allow 22/tcp"),
        ):
            with self.subTest(targets=targets, raw=raw):
                self.assertEqual(run_guard(targets=targets, raw=raw, added=added), 0)

    def test_guard_rejects_custom_policy_during_pending_apply(self):
        if not ANSIBLE.is_file():
            self.skipTest("missing project Ansible virtual environment")
        self.assertNotEqual(run_guard(targets=("custom-after",)), 0)
        self.assertNotEqual(run_guard(raw="-A ufw-user-input -p tcp --dport 80 -j ACCEPT"), 0)
        self.assertNotEqual(run_guard(raw="*nat"), 0)


if __name__ == "__main__":
    unittest.main()
