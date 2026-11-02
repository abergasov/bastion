# Spec Delta

## MODIFIED Requirements

### Requirement: Pinned integration and runtime secrets
The ssh_notify integration SHALL use a pinned Ansible-delivered artifact and
runtime secrets instead of an unpinned checkout or Telegram credentials in Make
arguments. Its complete application configuration, including Telegram values and
non-secret settings, SHALL be stored in Git as Ansible Vault ciphertext. Vault
password and ciphertext SHALL remain controller-side; Ansible SHALL deliver the
complete configuration as a root-only persistent server file and atomically
project it to `/run/secrets` for the service at boot. No manual reconstruction,
plaintext Git, inventory/template, fact-cache, log, diff or command-argument
path is permitted.

#### Scenario: Deploy the complete encrypted configuration
- **WHEN** an authorized controller deploys ssh_notify
- **THEN** it supplies the complete configuration from Vault without exposing
  Telegram values to arguments or tracked automation
- **AND** after reboot the service obtains the protected runtime file without a
  Vault password on the VPS

#### Scenario: Build and configure the integration
- **WHEN** the pinned artifact is built and configured
- **THEN** credentials are supplied from Vault at controller deployment time only

#### Scenario: Restore notification configuration on a replacement VPS
- **WHEN** a replacement VPS is configured after host compromise
- **THEN** the controller deploys a rotated complete Vault configuration and the
  replacement has no ability to decrypt Vault ciphertext
