#!/usr/bin/env python3
"""Exercise UFW manifest path-set validation without a host firewall."""

import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).parents[1]
TASKS = ROOT / "roles/firewall/tasks/main.yml"
ANSIBLE = ROOT / ".venv/bin/ansible-playbook"
V1 = (
    "/etc/default/ufw", "/etc/ufw/before.rules", "/etc/ufw/before6.rules",
    "/etc/ufw/user.rules", "/etc/ufw/user6.rules",
)
V2 = V1 + (
    "/etc/ufw/ufw.conf", "/etc/ufw/sysctl.conf", "/etc/ufw/after.rules",
    "/etc/ufw/after6.rules", "/etc/ufw/before.init", "/etc/ufw/after.init",
)


def task_block() -> str:
    source = TASKS.read_text()
    start = source.index("- name: Require the exact managed UFW state manifest paths")
    end = source.index("- name: Read packaged UFW policy input checksums", start)
    return source[start:end]


def run(paths: tuple[str, ...]) -> int:
    lines = "\n".join(f"      - {'a' * 64}  {path}" for path in paths)
    play = f"""---
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    firewall_ufw_manifest: {{stat: {{exists: true}}}}
    firewall_ufw_pending: {{stat: {{exists: false}}}}
    firewall_ufw_manifest_contents:
      stdout_lines:
{lines}
  tasks:
    {task_block().replace(chr(10), chr(10) + '    ').rstrip()}
"""
    with tempfile.TemporaryDirectory(prefix="bastion-ufw-manifest-") as directory:
        temp = Path(directory)
        play_path = temp / "play.yml"
        play_path.write_text(play)
        env = os.environ | {"ANSIBLE_LOCAL_TEMP": str(temp / "local"), "ANSIBLE_HOME": str(temp / "home")}
        return subprocess.run([str(ANSIBLE), "-i", "localhost,", str(play_path)], cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT).returncode


def main() -> None:
    if not ANSIBLE.is_file():
        raise SystemExit("missing project Ansible virtual environment")
    if run(V1) != 0 or run(V2) != 0:
        raise SystemExit("complete managed manifest unexpectedly failed")
    if run(V1[:-1]) == 0 or run(V2[:-1]) == 0 or run(V1 + ("/etc/ufw/after.rules",)) == 0:
        raise SystemExit("truncated or mixed manifest unexpectedly passed")


if __name__ == "__main__":
    main()
