#!/usr/bin/env python3
"""Regression checks for Ubuntu UFW's canonical numbered-rule output."""

import re
import unittest
from pathlib import Path


TASKS = Path(__file__).parents[1] / "roles/firewall/tasks/main.yml"


def task_regex(name: str) -> str:
    source = TASKS.read_text()
    match = re.search(
        rf"{name}:(?: >-\n      | )(?P<value>[^\n]+)", source
    )
    if not match:
        raise AssertionError(f"missing {name} in {TASKS}")
    return match.group("value").strip("'").replace("{{ netplan_interface }}", "ens4").replace("\\\\", "\\")


NUMBERED = task_regex("firewall_ufw_numbered_rule")
INBOUND = task_regex("firewall_ufw_inbound_rule")
ROUTE = task_regex("firewall_ufw_route_rule")
MANAGED = re.compile(NUMBERED + "(" + INBOUND + "|" + ROUTE + r")\s*$")
SOURCE = TASKS.read_text()
NUMBERED_SELECT = re.compile(r"^\[\s*[0-9]+\]")


class UfwStatusTest(unittest.TestCase):
    def test_accepts_canonical_managed_output(self):
        rules = (
            "[ 1] 22/tcp                     ALLOW IN    Anywhere                  ",
            "[ 2] 443/udp                    ALLOW IN    Anywhere                  ",
            "[ 4] Anywhere on ens4           ALLOW FWD   Anywhere on tun-openvpn   ",
            "[ 7] 22/tcp (v6)                ALLOW IN    Anywhere (v6)             ",
            "[10] Anywhere (v6) on ens4      ALLOW FWD   Anywhere (v6) on wg-bastion",
        )
        self.assertTrue(all(MANAGED.match(rule) for rule in rules))

    def test_rejects_stale_or_reversed_rules(self):
        rules = (
            "[11] 80/tcp ALLOW IN Anywhere",
            "[12] Anywhere on tun-openvpn ALLOW FWD Anywhere on ens4",
            "[13] Anywhere on ens4 ALLOW FWD Anywhere on eth9",
        )
        self.assertTrue(all(MANAGED.match(rule) is None for rule in rules))

    def test_complete_select_and_reject_rejects_stale_rule(self):
        lines = (
            "[ 1] 80/tcp ALLOW IN Anywhere",
            "[ 2] 443/tcp ALLOW IN Anywhere",
        )
        numbered = [line for line in lines if NUMBERED_SELECT.match(line)]
        self.assertEqual(len(numbered), 2)
        self.assertEqual([line for line in numbered if MANAGED.match(line) is None], [lines[0]])

    def test_task_uses_same_complete_line_guard(self):
        self.assertIn(
            "firewall_ufw_numbered_rule ~ '(' ~ firewall_ufw_inbound_rule ~ '|' ~ firewall_ufw_route_rule ~ ')\\s*$'",
            SOURCE,
        )
        self.assertEqual(SOURCE.count("select('match', '^\\[\\s*[0-9]+\\]')"), 2)


if __name__ == "__main__":
    unittest.main()
