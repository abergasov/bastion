# Tasks

- [x] 1. Remove exact-release checks from preflight and the platform role; add focused regressions for multiple Ubuntu releases and other distributions.
- [x] 2. Update platform requirements, decision notes and current documentation without rewriting historical VM evidence.
- [x] 3. Run focused tests, syntax and strict OpenSpec validation; review the diff.

Verification: `tests/preflight-bastion-test.sh`, `tests/platform-static-test.sh`,
`make syntax`, strict OpenSpec specs/changes validation and `git diff --check`
passed. Syntax used a writable Ansible temporary directory and the existing
`/tmp/bastion-firewall-collections` installation of `community.general`.
No VM, live host or cross-release package compatibility checks were run.
