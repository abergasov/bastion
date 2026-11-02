# Tasks

## 1. Simplify the firewall role

- [x] 1.1 Replace manifest, retry, foreign-policy, fresh-SSH and legacy-firewall migration machinery in `roles/firewall/tasks/main.yml` with direct UFW package, template, default, ingress, route and single-enable tasks; verify Ansible syntax.
- [x] 1.2 Retain the IPv4/IPv6 templates only for four NAT pools and isolation-before-conntrack ordering; verify a focused static regression covers every retained rule.

## 2. Synchronize contract and checks

- [x] 2.1 Remove obsolete firewall helper, fixtures and guard/retry/manifest tests; update VPN static checks for TCP/22, TCP/80, TCP/443, `ansible_port`, UDP/443, routes, NAT and isolation.
- [x] 2.2 Update the main VPN specification and operator documentation to describe the allowed TCP/80/custom SSH ingress and direct UFW policy; verify strict OpenSpec validation.

## 3. Verify the reduced policy

- [x] 3.1 Run focused firewall/VPN static tests, `make syntax`, `make test` and review the final diff; record unavailable or unrun disposable-VM/live checks.
  - Disposable-VM and live-VPS checks were not run; deployment remains separately authorized.
