# SSH Notifications Specification

## Purpose

Define Telegram notifications for SSH logins and server boots/reboots through the
owner's ssh_notify integration. Integration is not yet implemented or verified.

## Requirements

### Requirement: SSH login notifications

Bastion SHALL integrate the owner's `abergasov/ssh_notify` to send Telegram
notifications for SSH logins. Compatibility with the selected NixOS OpenSSH log
format SHALL be tested, including actual login events and log rotation. Historical
upstream observations are in [research](../../notes/research.md); journal support
SHALL NOT be assumed without verification.

If compatibility checks show that the selected NixOS log format is unsupported,
the integration MAY patch `ssh_notify` to support that format. Such a patch SHALL
be limited to the demonstrated compatibility need, include a focused regression
test using representative log entries, and be included reproducibly in the pinned
Nix package.

#### Scenario: Successful SSH login
- **WHEN** an administrator completes a fresh SSH login and Telegram delivery is available
- **THEN** the integration recognizes the actual log event and sends a login notification

#### Scenario: Log rotation
- **WHEN** the selected authentication log rotates and a subsequent SSH login occurs
- **THEN** the integration continues to recognize and notify about the new login

#### Scenario: Patch an unsupported log format
- **WHEN** compatibility testing demonstrates that `ssh_notify` cannot recognize the selected NixOS SSH login log format
- **THEN** a targeted compatibility patch is permitted and covered by a regression test
- **AND** the packaged integration is verified against actual login events and log rotation

### Requirement: Explicit boot and reboot notifications

Bastion SHALL notify about server boots/reboots explicitly. A notification that
the notification service started SHALL NOT alone be treated as proof of a server
reboot. Service restart and actual reboot behavior SHALL be tested separately.

#### Scenario: Server reboot
- **WHEN** the server reboots and notification delivery is available
- **THEN** a notification identifies the server boot/reboot

#### Scenario: Notification service restart
- **WHEN** only the notification service restarts
- **THEN** that event is not misrepresented as a server reboot

### Requirement: Pinned integration and runtime secrets

The ssh_notify integration SHALL use a pinned Nix package and runtime secrets
instead of an unpinned checkout or Telegram credentials in Make arguments.
The entire ssh_notify application configuration, including Telegram credentials
and all other configuration values, SHALL be stored in Git as SOPS/age ciphertext
using the same owner and VPS recipients as account-password secrets. Deployment
and recovery SHALL use that encrypted configuration as their source. sops-nix
SHALL decrypt the complete configuration into a protected runtime file under
`/run/secrets` for the service to read; plaintext SHALL NOT enter Git, Nix
expressions, `/nix/store`, logs or command arguments.
Notification contents and delivery guarantees remain open; notifications SHALL NOT
be presented as a complete audit trail without supporting guarantees.

#### Scenario: Build and configure the integration
- **WHEN** the integration is packaged and configured
- **THEN** its source revision is fixed and credentials are supplied at runtime
- **AND** no credentials appear in Make arguments or generated public build artifacts

#### Scenario: Deploy the complete encrypted configuration
- **WHEN** ssh_notify is deployed from the repository
- **THEN** sops-nix decrypts the complete application configuration into a protected runtime file read by the service
- **AND** all configuration values, including Telegram credentials, come from the encrypted configuration without manual reconstruction

#### Scenario: Restore notification configuration on a replacement VPS
- **WHEN** the VPS is recreated and the owner updates the SOPS recipients for the replacement host
- **THEN** deployment restores the complete ssh_notify configuration from the encrypted repository state
- **AND** credentials exposed in a host compromise are rotated before reuse
