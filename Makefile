.PHONY: install-bastion test

install-bastion:
	./scripts/install-bastion

test:
	./tests/install-bastion-test.sh
