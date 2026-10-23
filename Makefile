.PHONY: bootstrap apply maintenance test syntax

export PATH := $(CURDIR)/.venv/bin:$(PATH)

SECRETS_INPUT ?= inventory/secrets-input.json

bootstrap:
	./scripts/preflight-bastion
	./scripts/preflight-secrets $(SECRETS_INPUT)
	ansible-playbook -i inventory/hosts.ini playbooks/bootstrap.yml --extra-vars @$(SECRETS_INPUT) --extra-vars bastion_apply_final_ssh_policy=false --ssh-common-args='-o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=inventory/known_hosts -o StrictHostKeyChecking=yes'

apply:
	./scripts/preflight-secrets $(SECRETS_INPUT)
	ansible-playbook -i inventory/hosts.ini playbooks/site.yml --extra-vars @$(SECRETS_INPUT) --extra-vars ansible_user=admin --extra-vars bastion_apply_final_ssh_policy=true --ask-become-pass --ssh-common-args='-o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=inventory/known_hosts -o StrictHostKeyChecking=yes'

maintenance:
	./scripts/preflight-secrets $(SECRETS_INPUT)
	ansible-playbook -i inventory/hosts.ini playbooks/maintenance.yml --extra-vars @$(SECRETS_INPUT) --extra-vars ansible_user=admin --extra-vars bastion_apply_final_ssh_policy=true --ask-become-pass --ssh-common-args='-o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=inventory/known_hosts -o StrictHostKeyChecking=yes'

syntax:
	ansible-playbook -i inventory/hosts.ini.example playbooks/bootstrap.yml --syntax-check
	ansible-playbook -i inventory/hosts.ini.example playbooks/site.yml --syntax-check
	ansible-playbook -i inventory/hosts.ini.example playbooks/maintenance.yml --syntax-check

test:
	./tests/preflight-bastion-test.sh
	./tests/preflight-secrets-test.sh
	./tests/platform-static-test.sh
	./tests/secrets-static-test.sh
	./tests/vault-import-contract-test.sh
