#!/usr/bin/env python3
"""Exercise the UFW preflight guard for policy files hidden from `ufw status`."""

import os
import base64
import hashlib
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).parents[1]
TASKS = ROOT / "roles/firewall/tasks/main.yml"
ANSIBLE = ROOT / ".venv/bin/ansible-playbook"
POLICY_FILES = (
    "/etc/default/ufw",
    "/etc/ufw/ufw.conf",
    "/etc/ufw/sysctl.conf",
    "/etc/ufw/before.rules",
    "/etc/ufw/before6.rules",
    "/etc/ufw/after.rules",
    "/etc/ufw/after6.rules",
    "/etc/ufw/before.init",
    "/etc/ufw/after.init",
)


def quoted(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def task_block() -> str:
    source = TASKS.read_text()
    start = source.index("- name: Reject unrecognized fresh UFW policy inputs")
    end = source.index("- name: Read existing UFW user rules", start)
    return source[start:end]


def playbook(
    changed_path: str | None = None,
    executable_hook: str | None = None,
    managed: bool = False,
    ufw_conf: str = "ENABLED=no\nLOGLEVEL=low\n",
) -> str:
    package_hashes = {path: f"a{index:031x}" for index, path in enumerate(POLICY_FILES, 1)}
    package_hashes["/etc/ufw/ufw.conf"] = hashlib.md5(b"ENABLED=no\nLOGLEVEL=low\n").hexdigest()
    hashes = package_hashes.copy()
    if changed_path:
        hashes[changed_path] = "f" * 32
    conffiles = "\n".join(
        f"      - {quoted(f' {path} {package_hashes[path]}') }"
        for path in ("/etc/default/ufw", "/etc/ufw/sysctl.conf")
    )
    skeletons = "\n".join(
        f"      - {quoted(f'{package_hashes[path]}  /usr/share/ufw/{path.removeprefix('/etc/ufw/')}') }"
        for path in POLICY_FILES
        if path not in ("/etc/default/ufw", "/etc/ufw/sysctl.conf")
    )
    results = "\n".join(
        "      - item: "
        + path
        + "\n        stat:\n"
        + "          exists: true\n"
        + f"          checksum: {hashes[path]}\n"
        + f"          executable: {'true' if path == executable_hook else 'false'}"
        for path in POLICY_FILES
    )
    return f"""---
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    firewall_ufw_marker: {{rc: {0 if managed else 1}}}
    firewall_ufw_manifest: {{stat: {{exists: {str(managed).lower()}}}}}
    firewall_ufw_state_version: {{stat: {{exists: {str(managed).lower()}}}}}
    firewall_ufw_state_version_contents: {{stdout: bastion-ufw-state-v1}}
    firewall_ufw_manifest_check: {{rc: 0}}
    firewall_ufw_conf:
      content: {quoted(base64.b64encode(ufw_conf.encode()).decode())}
    firewall_ufw_package_conffiles:
      stdout_lines:
{conffiles}
    firewall_ufw_package_skeletons:
      stdout_lines:
{skeletons}
    firewall_ufw_policy_inputs:
      results:
{results}
  tasks:
    {task_block().replace(chr(10), chr(10) + '    ').rstrip()}
"""


def run(**kwargs: str | None) -> int:
    with tempfile.TemporaryDirectory(prefix="bastion-ufw-policy-inputs-") as directory:
        temp = Path(directory)
        play = temp / "play.yml"
        play.write_text(playbook(**kwargs))
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
    if run() != 0:
        raise SystemExit("fresh package policy inputs unexpectedly failed")
    for path in ("/etc/ufw/after.rules", "/etc/ufw/after6.rules", "/etc/ufw/sysctl.conf"):
        if run(changed_path=path) == 0:
            raise SystemExit(f"custom {path} unexpectedly passed")
    for path in ("/etc/ufw/before.init", "/etc/ufw/after.init"):
        if run(executable_hook=path) == 0:
            raise SystemExit(f"executable {path} unexpectedly passed")
    for path in ("/etc/ufw/after.rules", "/etc/ufw/after6.rules"):
        if run(changed_path=path, managed=True) == 0:
            raise SystemExit(f"managed v1 custom {path} unexpectedly passed")
    if run(executable_hook="/etc/ufw/after.init", managed=True) == 0:
        raise SystemExit("managed v1 executable hook unexpectedly passed")
    if run(managed=True, ufw_conf="ENABLED=yes\nLOGLEVEL=low\nEXTRA=custom\n") == 0:
        raise SystemExit("managed v1 custom ufw.conf unexpectedly passed")


if __name__ == "__main__":
    main()
