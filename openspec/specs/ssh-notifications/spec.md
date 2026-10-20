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
Notification contents remain open. Notifications SHALL NOT be presented as a
complete audit trail: delivery uses the bounded retry policy below.

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

### Requirement: Application-owned notification delivery and retries

ssh_notify SHALL own notification generation and Telegram delivery for SSH logins
and server boots/reboots, including retry handling. After an unsuccessful initial
send, it SHALL retry up to five times for that notification, stopping on success
(at most six send attempts in total). If all attempts fail, loss of that
notification is accepted; durable queuing or guaranteed eventual delivery is not
required. Exhaustion SHALL be reported without exposing secrets, and SHALL NOT
prevent processing subsequent notifications.

A targeted ssh_notify patch MAY implement this behavior. The patch SHALL include
focused regression tests and be packaged reproducibly in the pinned Nix package.
Bastion SHALL NOT add a separate sender, retry wrapper or delivery queue.

#### Scenario: Delivery succeeds during retries
- **WHEN** the initial send fails and a subsequent attempt succeeds
- **THEN** ssh_notify stops retrying that notification without using more than five retries

#### Scenario: Delivery attempts are exhausted
- **WHEN** the initial send and all five retries fail
- **THEN** ssh_notify reports the failure without exposing secrets and makes no further attempts for that notification
- **AND** subsequent notifications continue to be processed

#### Scenario: Verify a delivery patch
- **WHEN** a patch adds the agreed delivery behavior to ssh_notify
- **THEN** regression tests cover immediate success, success during retries and exhaustion using a mock endpoint
- **AND** the pinned Nix package includes the patch without a separate Bastion delivery mechanism
