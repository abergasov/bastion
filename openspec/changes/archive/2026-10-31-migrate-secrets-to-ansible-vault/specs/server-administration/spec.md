# Spec Delta

## MODIFIED Requirements

### Requirement: Initial account passwords and privilege elevation
Initial provisioning SHALL set the owner-supplied `admin` and `root` passwords
from controller-side Ansible Vault data. The Vault password SHALL remain on the
controller; only root-owned persistent server password-hash files and their
protected runtime projection may reach the VPS. This SHALL not enable SSH
password authentication.

#### Scenario: Provision account passwords
- **WHEN** an authorized controller applies the configuration with its protected
  Vault password source
- **THEN** the two password hashes are delivered without plaintext in task output
  or command arguments and SSH remains public-key-only

#### Scenario: Obtain root privileges as admin
- **WHEN** admin supplies the configured root password to `su`
- **THEN** correct authentication opens a root shell and incorrect authentication does not
