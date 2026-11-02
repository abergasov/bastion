## MODIFIED Requirements

### Requirement: Repeatable Ubuntu Server configuration

Bastion SHALL configure an ordinary x86_64 Ubuntu Server through Ansible
playbooks and roles, running OpenVPN, WireGuard, fail2ban and the owner's
ssh_notify integration. The local project `/home/alejandro/go/src/ansible`
SHALL serve as a read-only reference; its settings SHALL be checked against
the current specifications before reuse. Needed secrets MAY be copied under
the secret-handling requirements in [recovery-and-verification](../recovery-and-verification/spec.md).
Migration of existing VPN credentials and backward compatibility with the previous
server are not required.

Provisioning SHALL require Ubuntu but SHALL NOT reject a host solely because
of its Ubuntu release number. Implementation SHALL document the releases used
for verification, verify component compatibility against official sources, and
record the Ansible and collection versions used. Acceptance by distribution
checks SHALL NOT be presented as proof of compatibility with every Ubuntu release.
External source artifacts SHALL have
fixed revisions and integrity checks. Routine configuration SHALL NOT implicitly
upgrade the system. Ansible reruns with unchanged inputs SHALL converge without
unnecessary changes, service restarts or credential replacement. This does not
promise bit-for-bit reproducible Ubuntu images.

#### Scenario: Configure a new server
- **WHEN** the administrator prepares a new host
- **THEN** its services and persistent networking are configured through Ansible
- **AND** installation does not depend on importing credentials from the previous server
- **AND** the Ubuntu release used for verification and automation dependency versions are recorded

#### Scenario: Repeat configuration
- **WHEN** Ansible runs again with unchanged inputs on a configured host
- **THEN** managed state remains unchanged without unnecessary restarts
- **AND** current credentials, membership and revocations remain effective

#### Scenario: Validate distribution without a release pin
- **WHEN** preflight or the platform role checks a target distribution
- **THEN** Ubuntu passes the distribution check regardless of its release number
- **AND** a non-Ubuntu distribution is rejected
- **AND** SSH identity, privilege and other configuration checks remain required

