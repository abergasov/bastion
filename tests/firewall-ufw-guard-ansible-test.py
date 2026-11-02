#!/usr/bin/env python3
"""Execute the exact firewall stale-rule assertion with Ansible fixtures."""

import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).parents[1]
TASKS = ROOT / "roles/firewall/tasks/main.yml"
ANSIBLE = ROOT / ".venv/bin/ansible-playbook"

CANONICAL = [
    "[ 1] 22/tcp                     ALLOW IN    Anywhere                  ",
    "[ 2] 443/tcp                    ALLOW IN    Anywhere                  ",
    "[ 3] 443/udp                    ALLOW IN    Anywhere                  ",
    "[ 4] Anywhere on ens4           ALLOW FWD   Anywhere on tun-openvpn   ",
    "[ 5] Anywhere on ens4           ALLOW FWD   Anywhere on wg-bastion    ",
    "[ 6] 22/tcp (v6)                ALLOW IN    Anywhere (v6)             ",
    "[ 7] 443/tcp (v6)               ALLOW IN    Anywhere (v6)             ",
    "[ 8] 443/udp (v6)               ALLOW IN    Anywhere (v6)             ",
    "[ 9] Anywhere (v6) on ens4      ALLOW FWD   Anywhere (v6) on tun-openvpn",
    "[10] Anywhere (v6) on ens4      ALLOW FWD   Anywhere (v6) on wg-bastion ",
]


def quoted(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def task_block() -> str:
    source = TASKS.read_text()
    start = source.index("- name: Reject stale rules in the active Bastion UFW policy")
    end = source.index("- name: Detect whether the managed UFW policy needs an apply marker", start)
    return source[start:end]


def playbook(lines: list[str], routed: str) -> str:
    rendered_lines = "\n".join(f"      - {quoted(line)}" for line in lines)
    return f"""---
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    netplan_interface: ens4
    firewall_ufw_marker: {{rc: 0}}
    firewall_ufw_manifest: {{stat: {{exists: true}}}}
    firewall_ufw_state_version: {{stat: {{exists: true}}}}
    firewall_ufw_state_version_contents: {{stdout: bastion-ufw-state-v1}}
    firewall_ufw_manifest_check: {{rc: 0}}
    firewall_ufw_pending_valid: false
    firewall_ufw_status:
      stdout: {quoted('Status: active\\nDefault: deny (incoming), allow (outgoing), ' + routed + ' (routed)')}
    firewall_ufw_numbered:
      stdout_lines:
{rendered_lines}
  tasks:
    {task_block().replace(chr(10), chr(10) + '    ').rstrip()}
"""


def run(lines: list[str], routed: str) -> int:
    with tempfile.TemporaryDirectory(prefix="bastion-ufw-guard-") as directory:
        temp = Path(directory)
        play = temp / "play.yml"
        play.write_text(playbook(lines, routed))
        env = os.environ | {
            "ANSIBLE_LOCAL_TEMP": str(temp / "local"),
            "ANSIBLE_HOME": str(temp / "home"),
        }
        return subprocess.run(
            [str(ANSIBLE), "-i", "localhost,", str(play)],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        ).returncode


def main() -> None:
    if not ANSIBLE.is_file():
        raise SystemExit("missing project Ansible virtual environment")
    for routed in ("deny", "disabled"):
        if run(CANONICAL, routed) != 0:
            raise SystemExit(f"canonical {routed} fixture failed")
    invalid = {
        "stale": "[ 1] 80/tcp ALLOW IN Anywhere",
        "reversed": "[ 1] Anywhere on tun-openvpn ALLOW FWD Anywhere on ens4",
        "wrong-interface": "[ 1] Anywhere on ens4 ALLOW FWD Anywhere on eth9",
    }
    for name, line in invalid.items():
        fixture = CANONICAL.copy()
        fixture[0] = line
        if run(fixture, "deny") == 0:
            raise SystemExit(f"{name} fixture unexpectedly passed")
    if run(CANONICAL[:-1], "deny") == 0:
        raise SystemExit("missing-rule fixture unexpectedly passed")


if __name__ == "__main__":
    main()
