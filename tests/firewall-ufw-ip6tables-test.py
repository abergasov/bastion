#!/usr/bin/env python3
"""Regression check for the IPv6 UFW chain names emitted by iptables-nft."""

import unittest
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GUEST_CHECK = ROOT / "tests/vpn-vm-guest-test.sh"
VM_CHECK = ROOT / "tests/vpn-vm-test.sh"

# Relevant lines captured by the disposable Ubuntu 26.04 UFW runtime inspector.
IP6TABLES_SAVE_CAPTURE = """\
*filter
:ufw6-before-forward - [0:0]
:ufw6-user-forward - [0:0]
-A FORWARD -j ufw6-before-forward
-A ufw6-before-forward -j ufw6-user-forward
COMMIT
"""


class UfwIpv6RuntimeTest(unittest.TestCase):
    def test_captured_ubuntu_ipv6_forward_chain_uses_ufw6_prefix(self):
        self.assertIn(":ufw6-before-forward - [0:0]", IP6TABLES_SAVE_CAPTURE)
        self.assertIn("-A FORWARD -j ufw6-before-forward", IP6TABLES_SAVE_CAPTURE)
        self.assertNotIn("-A FORWARD -j ufw-before-forward", IP6TABLES_SAVE_CAPTURE)

    def test_runtime_and_reload_checks_match_the_captured_chain(self):
        expected = "ip6tables-save | grep -F 'ufw6-before-forward' >/dev/null"
        self.assertIn(expected, GUEST_CHECK.read_text())
        self.assertIn(expected, VM_CHECK.read_text())

    def test_pipefail_safe_matcher_consumes_a_large_ip6tables_stream(self):
        command = r'''
set -o pipefail
{ printf '%s\n' '-A FORWARD -j ufw6-before-forward'; dd if=/dev/zero bs=65536 count=32 2>/dev/null; } |
  grep -F 'ufw6-before-forward' >/dev/null
'''
        completed = subprocess.run(
            ["bash", "-c", command], capture_output=True, text=True, check=False
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)


if __name__ == "__main__":
    unittest.main()
