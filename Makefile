.PHONY: bootstrap apply maintenance test recovery-integration-test syntax ssh-notifications-test ssh-notifications-vm-test vpn-vm-test vpn-add-wg vpn-add-open vpn-list-wg vpn-list-open vpn-export-wg vpn-export-open vpn-revoke-wg vpn-revoke-open vpn-renew-open

export PATH := $(CURDIR)/.venv/bin:$(PATH)
export VPN_HOST CLIENT

SSH_COMMON_ARGS := -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=inventory/known_hosts -o StrictHostKeyChecking=yes
SSH_COMMON_ARGS_JSON := {"ansible_ssh_common_args":"$(SSH_COMMON_ARGS)"}

SECRETS_INPUT ?= inventory/secrets-input.json
VAULT_PASSWORD_FILE ?= /home/alejandro/go/src/ansible/vault.txt

bootstrap:
	./scripts/preflight-bastion
	BASTION_VAULT_PASSWORD_FILE=$(VAULT_PASSWORD_FILE) ./scripts/preflight-secrets $(SECRETS_INPUT)
	ansible-playbook --vault-password-file $(VAULT_PASSWORD_FILE) -i inventory/hosts.ini playbooks/bootstrap.yml --extra-vars @$(SECRETS_INPUT) --extra-vars bastion_apply_final_ssh_policy=false --extra-vars '$(SSH_COMMON_ARGS_JSON)' --ssh-common-args='$(SSH_COMMON_ARGS)'

apply:
	BASTION_VAULT_PASSWORD_FILE=$(VAULT_PASSWORD_FILE) ./scripts/preflight-secrets $(SECRETS_INPUT)
	ansible-playbook --vault-password-file $(VAULT_PASSWORD_FILE) -i inventory/hosts.ini playbooks/site.yml --extra-vars @$(SECRETS_INPUT) --extra-vars ansible_user=admin --extra-vars bastion_apply_final_ssh_policy=true --extra-vars '$(SSH_COMMON_ARGS_JSON)' --ask-become-pass --ssh-common-args='$(SSH_COMMON_ARGS)'

maintenance:
	BASTION_VAULT_PASSWORD_FILE=$(VAULT_PASSWORD_FILE) ./scripts/preflight-secrets $(SECRETS_INPUT)
	ansible-playbook --vault-password-file $(VAULT_PASSWORD_FILE) -i inventory/hosts.ini playbooks/maintenance.yml --extra-vars @$(SECRETS_INPUT) --extra-vars ansible_user=admin --extra-vars bastion_apply_final_ssh_policy=true --extra-vars '$(SSH_COMMON_ARGS_JSON)' --ask-become-pass --ssh-common-args='$(SSH_COMMON_ARGS)'

syntax:
	ansible-playbook -i inventory/hosts.ini.example playbooks/bootstrap.yml --syntax-check
	ansible-playbook -i inventory/hosts.ini.example playbooks/site.yml --syntax-check
	ansible-playbook -i inventory/hosts.ini.example playbooks/maintenance.yml --syntax-check

test:
	./tests/preflight-bastion-test.sh
	./tests/preflight-secrets-test.sh
	./tests/platform-static-test.sh
	./tests/secrets-static-test.sh
	./tests/runtime-secrets-activation-test.sh
	./tests/vault-import-contract-test.sh
	./tests/vpn-static-test.sh
	SSH_NOTIFY_SKIP_PACKAGE_TEST=1 ./tests/ssh-notifications-test.sh
	python3 ./tests/device-lifecycle-test.py
	python3 ./tests/crl-renewal-test.py
	./tests/server-crl-renewal-test.sh
	python3 ./tests/authority-marker-test.py

recovery-integration-test:
	./tests/recovery-integration-test.sh

ssh-notifications-test:
	./tests/ssh-notifications-test.sh

ssh-notifications-vm-test:
	./tests/ssh-notifications-vm-test.sh

vpn-vm-test:
	./tests/vpn-vm-test.sh

vpn-add-wg:
	@test -n "$${VPN_HOST:-}" && test -n "$${CLIENT:-}" || (echo 'VPN_HOST and CLIENT are required' >&2; exit 2)
	python3 ./scripts/bastion-vpn-lifecycle add-wg --vpn-host "$${VPN_HOST}" --client "$${CLIENT}"

vpn-add-open:
	@test -n "$${VPN_HOST:-}" && test -n "$${CLIENT:-}" || (echo 'VPN_HOST and CLIENT are required' >&2; exit 2)
	python3 ./scripts/bastion-vpn-lifecycle add-open --vpn-host "$${VPN_HOST}" --client "$${CLIENT}"

vpn-list-wg vpn-list-open:
	@test -n "$${VPN_HOST:-}" || (echo 'VPN_HOST is required' >&2; exit 2)
	python3 ./scripts/bastion-vpn-lifecycle $(patsubst vpn-%,%,$@) --vpn-host "$${VPN_HOST}"

vpn-export-wg vpn-export-open:
	@test -n "$${VPN_HOST:-}" && test -n "$${CLIENT:-}" || (echo 'VPN_HOST and CLIENT are required' >&2; exit 2)
	python3 ./scripts/bastion-vpn-lifecycle $(patsubst vpn-%,%,$@) --vpn-host "$${VPN_HOST}" --client "$${CLIENT}"

vpn-revoke-wg vpn-revoke-open:
	@test -n "$${VPN_HOST:-}" || (echo 'VPN_HOST is required' >&2; exit 2)
	python3 ./scripts/bastion-vpn-lifecycle $(patsubst vpn-%,%,$@) --vpn-host "$${VPN_HOST}"

vpn-renew-open:
	@test -n "$${VPN_HOST:-}" || (echo 'VPN_HOST is required' >&2; exit 2)
	python3 ./scripts/bastion-vpn-lifecycle renew-open --vpn-host "$${VPN_HOST}"
