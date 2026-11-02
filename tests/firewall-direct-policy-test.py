#!/usr/bin/env python3
"""Static contract for Bastion's direct UFW policy."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TASKS = (ROOT / "roles/firewall/tasks/main.yml").read_text()
TEMPLATES = (
    ROOT / "roles/firewall/templates/before.rules.j2",
    ROOT / "roles/firewall/templates/before6.rules.j2",
)


def task(name: str) -> str:
    start = TASKS.index(f"- name: {name}")
    end = TASKS.find("\n- name:", start + 1)
    return TASKS[start:] if end == -1 else TASKS[start:end]


class DirectUfwPolicyTest(unittest.TestCase):
    def test_direct_defaults_ingress_routes_and_single_enablement(self):
        install = task("Install UFW")
        self.assertIn("ansible.builtin.apt:", install)
        self.assertIn("name: ufw", install)
        self.assertIn("state: present", install)

        expected = {
            "Deny incoming UFW traffic by default": ("default: deny", "direction: incoming"),
            "Deny routed UFW traffic by default": ("default: deny", "direction: routed"),
            "Allow outgoing UFW traffic by default": ("default: allow", "direction: outgoing"),
            "Allow default SSH through UFW": ("direction: in", "proto: tcp", "port: '22'"),
            "Allow Ansible SSH through UFW": ("direction: in", "proto: tcp", "ansible_port | default(22, true)"),
            "Allow HTTP through UFW": ("direction: in", "proto: tcp", "port: '80'"),
            "Allow OpenVPN through UFW": ("direction: in", "proto: tcp", "port: '443'"),
            "Allow WireGuard through UFW": ("direction: in", "proto: udp", "port: '443'"),
        }
        for name, fragments in expected.items():
            with self.subTest(name=name):
                block = task(name)
                self.assertIn("community.general.ufw:", block)
                if "Allow" in name and "default" not in name:
                    self.assertIn("rule: allow", block)
                for fragment in fragments:
                    self.assertIn(fragment, block)

        for name, tunnel in (
            ("Allow OpenVPN tunnel egress through UFW", "tun-openvpn"),
            ("Allow WireGuard tunnel egress through UFW", "wg-bastion"),
        ):
            block = task(name)
            self.assertIn("community.general.ufw:", block)
            self.assertIn("rule: allow", block)
            self.assertIn("route: true", block)
            self.assertIn(f"interface_in: {tunnel}", block)
            self.assertIn('interface_out: "{{ netplan_interface }}"', block)

        enabled = task("Enable the Bastion UFW policy")
        self.assertEqual(enabled.count("state: enabled"), 1)
        self.assertEqual(TASKS.count("state: enabled"), 1)
        enablement = TASKS.index("Enable the Bastion UFW policy")
        for name in (*expected, "Allow OpenVPN tunnel egress through UFW", "Allow WireGuard tunnel egress through UFW"):
            self.assertLess(TASKS.index(name), enablement)

    def test_templates_keep_dual_stack_nat_and_isolation_before_conntrack(self):
        pools = (("10.42.0.0/24", "10.43.0.0/24"), ("fd42:1::/64", "fd42:2::/64"))
        drops = (
            "wg-bastion -o wg-bastion -j DROP",
            "tun-openvpn -o tun-openvpn -j DROP",
            "wg-bastion -o tun-openvpn -j DROP",
            "tun-openvpn -o wg-bastion -j DROP",
        )
        for template, expected_pools in zip(TEMPLATES, pools):
            with self.subTest(template=template.name):
                source = template.read_text()
                for pool in expected_pools:
                    self.assertIn(f"-s {pool} -o {{{{ netplan_interface }}}} -j MASQUERADE", source)
                last_drop = max(source.index(drop) for drop in drops)
                established = source.index("-m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT", last_drop)
                self.assertLess(last_drop, established)

    def test_obsolete_migration_machinery_is_absent(self):
        for fragment in (
            "manifest",
            "retry",
            "foreign",
            "policy inputs",
            "fresh SSH",
            "legacy",
            "bastion-ufw-state",
            "bastion-apply-pending",
            "bastion-verify-fresh-ssh",
            "nftables.service",
            "ufw, reload",
            "reset_connection",
            "wait_for_connection",
            "systemd_service",
        ):
            self.assertNotIn(fragment, TASKS)


if __name__ == "__main__":
    unittest.main()
