# Server Administration Specification

## Purpose

Define publicly reachable, key-authenticated administration and fail2ban
protection for the future NixOS VPN server.

## Requirements

### Requirement: Public key-only SSH

SSH SHALL remain publicly reachable and accept public-key authentication only.
Password authentication SHALL be forbidden. Administration SHALL NOT require VPN
connectivity or a public source-IP allowlist. For inbound administrator access,
only the administrator's public key SHALL be placed on the server; the previous
Ansible private-key restoration pattern SHALL NOT be reproduced.

#### Scenario: Administer without a VPN
- **WHEN** an authorized administrator connects from a public address without a VPN
- **THEN** SSH permits authentication with the authorized public key
- **AND** the source address does not need prior allowlisting

#### Scenario: Attempt password login
- **WHEN** a client attempts SSH authentication using a password
- **THEN** the server rejects that authentication method

### Requirement: fail2ban protection for public SSH

Bastion SHALL run fail2ban for public SSH and verify actual SSH log matching and
ban/unban behavior on both IPv4 and IPv6. Jail backend, thresholds, ban durations
and exemptions remain design choices awaiting agreement.

#### Scenario: Enforce the selected ban policy
- **WHEN** SSH failures from an IPv4 or IPv6 address meet the agreed jail policy
- **THEN** fail2ban detects the failures and enforces the configured SSH ban
- **AND** ban removal is verified to restore access under the same policy
