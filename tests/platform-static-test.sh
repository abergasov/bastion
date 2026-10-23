#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

! rg -n 'nixos-anywhere|disko|nix( |$)' Makefile scripts
test -d openspec/changes/archive
rg -qx 'host_key_checking = True' ansible.cfg
rg -q 'GlobalKnownHostsFile=/dev/null' Makefile scripts/preflight-bastion
rg -q 'StrictHostKeyChecking=yes' Makefile scripts/preflight-bastion
rg -q 'MaxRetentionSec=30day' roles/platform/tasks/main.yml
rg -U -q 'path: /var/log/journal\n    state: directory\n    owner: root\n    group: systemd-journal\n    mode: '\''2755'\''\n  notify: Restart journald' roles/platform/tasks/main.yml
rg -q 'rotate 30' roles/platform/tasks/main.yml
rg -q '/etc/cloud/cloud.cfg.d/99-bastion-disable-network-config.cfg' roles/platform/tasks/main.yml
rg -F -q 'network: {config: disabled}' roles/platform/tasks/main.yml
rg -q '/etc/netplan/50-cloud-init.yaml' roles/platform/tasks/main.yml
rg -U -q 'path: /etc/netplan/50-cloud-init.yaml\n    state: absent\n  notify: Apply Netplan' roles/platform/tasks/main.yml
template_line=$(rg -n 'Configure persistent provider networking' roles/platform/tasks/main.yml | cut -d: -f1)
disable_line=$(rg -n 'Disable future cloud-init network configuration' roles/platform/tasks/main.yml | cut -d: -f1)
remove_line=$(rg -n 'Remove only cloud-init generated Netplan configuration' roles/platform/tasks/main.yml | cut -d: -f1)
[ "$template_line" -lt "$disable_line" ] && [ "$disable_line" -lt "$remove_line" ]
rg -q 'upgrade: dist' playbooks/maintenance.yml
rg -U -q 'hosts: bastion_admin\n  remote_user: admin\n  become: true\n  become_method: ansible.builtin.su\n  gather_facts: true' playbooks/maintenance.yml
rg -q 'become_method: ansible.builtin.sudo' playbooks/bootstrap.yml
rg -q 'become_method: ansible.builtin.su' playbooks/site.yml playbooks/maintenance.yml
rg -q 'bastion_apply_final_ssh_policy=false' Makefile
test "$(rg -c 'bastion_apply_final_ssh_policy=true' Makefile)" = 2
rg -q 'Prove the fresh routine connection is admin' playbooks/site.yml
rg -U -q 'Prove the fresh routine connection is admin[\s\S]*changed_when: false\n      check_mode: false\n      become: false' playbooks/site.yml
rg -q 'name: secrets_administration' playbooks/maintenance.yml
rg -q 'name: administration' playbooks/maintenance.yml
rg -q 'argv:' playbooks/maintenance.yml
rg -U -q 'via: \{\{ ipv4_gateway \}\}\n          on-link: true' roles/platform/templates/99-bastion.yaml.j2
rg -U -q '\{\{ netplan_interface \}\}:\n      optional: true\n      dhcp4: false' roles/platform/templates/99-bastion.yaml.j2
rg -q 'nameservers:' roles/platform/templates/99-bastion.yaml.j2
rg -F -q 'addresses: {{ dns_servers | to_json }}' roles/platform/templates/99-bastion.yaml.j2
! rg -n 'upgrade:|state: latest' playbooks/bootstrap.yml playbooks/site.yml roles
