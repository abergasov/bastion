#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

private_age_prefix="AGE""-SECRET-KEY-"
if git grep -n -- "$private_age_prefix" -- ':!tests/secrets-static-test.sh'; then
  printf '%s\n' "private age identity found in tracked files" >&2
  exit 1
fi

allowed_secret_files='secrets/server.yaml'
while IFS= read -r path; do
  [ "$path" = "$allowed_secret_files" ] || {
    printf '%s\n' "unexpected tracked secret input: $path" >&2
    exit 1
  }
done < <(git ls-files 'secrets/*')

if git grep -inE '(^|[^[:alnum:]])(ca|client|enrollment|revocation)([^[:alnum:]]|$)' -- 'secrets/*'; then
  printf '%s\n' "owner-only credential material found in tracked secret input" >&2
  exit 1
fi

rg -q 'checksum: sha256:e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b' roles/secrets_administration/tasks/main.yml
rg -U -q 'Install age runtime[\s\S]*name: age[\s\S]*state: present[\s\S]*update_cache: true' roles/secrets_administration/tasks/main.yml
rg -q 'dest: /var/lib/bastion/age/identity.txt' roles/secrets_administration/tasks/main.yml
rg -q 'dest: /var/lib/bastion/secrets/server.yaml' roles/secrets_administration/tasks/main.yml
rg -q 'no_log: true' roles/secrets_administration/tasks/main.yml roles/administration/tasks/main.yml
rg -q 'diff: false' roles/secrets_administration/tasks/main.yml roles/administration/tasks/main.yml
rg -U -q 'Deliver VPS age identity[\s\S]*no_log: true\n  diff: false' roles/secrets_administration/tasks/main.yml
rg -U -q 'Deliver encrypted server secrets[\s\S]*no_log: true\n  diff: false' roles/secrets_administration/tasks/main.yml
rg -U -q 'Read stable admin password hash[\s\S]*no_log: true\n  diff: false' roles/administration/tasks/main.yml
rg -U -q 'Read stable root password hash[\s\S]*no_log: true\n  diff: false' roles/administration/tasks/main.yml
rg -U -q 'Read stable admin password hash[\s\S]*check_mode: false[\s\S]*no_log: true' roles/administration/tasks/main.yml
rg -U -q 'Read stable root password hash[\s\S]*check_mode: false[\s\S]*no_log: true' roles/administration/tasks/main.yml
rg -q 'rm -rf "\$runtime_dir"' roles/secrets_administration/templates/bastion-decrypt-secrets.sh.j2
rg -U -q 'install -d -m 0700 /run/secrets\nstaging_dir=\$\(mktemp -d /run/secrets/\.bastion\.XXXXXX\)' roles/secrets_administration/templates/bastion-decrypt-secrets.sh.j2
rg -q 'mktemp -d /run/secrets/.bastion.XXXXXX' roles/secrets_administration/templates/bastion-decrypt-secrets.sh.j2
rg -q 'mv "\$staging_dir" "\$runtime_dir"' roles/secrets_administration/templates/bastion-decrypt-secrets.sh.j2
rg -q 'ExecStartPre=/usr/bin/rm -rf /run/secrets/bastion' roles/secrets_administration/templates/bastion-secrets.service.j2
rg -U -q 'Enable and start runtime secrets[\s\S]*Require refreshed runtime secrets before dependent administration[\s\S]*ansible.builtin.meta: flush_handlers' roles/secrets_administration/tasks/main.yml
rg -q 'Requires=bastion-secrets.service' roles/secrets_administration/tasks/main.yml
rg -q 'dest: /etc/ssh/sshd_config.d/00-bastion-admin.conf' roles/administration/tasks/main.yml
rg -q 'AllowUsers admin' roles/administration/templates/90-bastion-admin.conf.j2
rg -q 'PermitRootLogin no' roles/administration/templates/90-bastion-admin.conf.j2
rg -q 'PasswordAuthentication no' roles/administration/templates/90-bastion-admin.conf.j2
rg -q 'KbdInteractiveAuthentication no' roles/administration/templates/90-bastion-admin.conf.j2
rg -q 'PubkeyAuthentication yes' roles/administration/templates/90-bastion-admin.conf.j2
rg -U -q 'Read effective SSH restriction configuration[\s\S]*- /usr/sbin/sshd[\s\S]*- -T[\s\S]*- -f[\s\S]*- /etc/ssh/sshd_config' roles/administration/tasks/main.yml
rg -U -q 'Read effective SSH restriction configuration[\s\S]*check_mode: false' roles/administration/tasks/main.yml
rg -q "'allowusers admin' in administration_sshd_effective.stdout_lines" roles/administration/tasks/main.yml
rg -q "'permitrootlogin no' in administration_sshd_effective.stdout_lines" roles/administration/tasks/main.yml
rg -q "'passwordauthentication no' in administration_sshd_effective.stdout_lines" roles/administration/tasks/main.yml
rg -q "'kbdinteractiveauthentication no' in administration_sshd_effective.stdout_lines" roles/administration/tasks/main.yml
rg -q "'pubkeyauthentication yes' in administration_sshd_effective.stdout_lines" roles/administration/tasks/main.yml
rg -q 'effective SSH configuration conflicts with Bastion' roles/administration/tasks/main.yml
rg -F -q 'export PATH := $(CURDIR)/.venv/bin:$(PATH)' Makefile
rg -q -- '--extra-vars ansible_user=admin' Makefile
rg -U -q 'Prove the fresh routine connection is admin[\s\S]*check_mode: false[\s\S]*become: false' playbooks/site.yml
! rg -n 'sudo' roles/administration
! rg -n 'DefaultDependencies=no' roles/secrets_administration
! rg -n 'backend =' roles/administration
! rg -n '^      filter =' roles/administration/tasks/main.yml
! rg -in -e '(^|[^[:alnum:]])(ca|client|enrollment|revocation)([^[:alnum:]]|$)' roles/secrets_administration
