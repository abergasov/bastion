# Design

## Context

Both bootstrap preflight and the Ansible platform role enforce Ubuntu 26.04.
The owner removed that policy; Ubuntu itself remains the target distribution.

## Decisions

Remove version comparisons directly, without adding an allowlist, minimum
release or bypass switch. Preserve SSH identity and privilege validation.
Test multiple release values through the existing synthetic SSH fixture and
the platform assertion. Retain the fixed disposable-VM image and historical
test records as evidence about that image only.

## Risks / Trade-offs

Passing distribution validation does not establish package or service compatibility
on every Ubuntu release. Target compatibility still requires verification.

## Migration Plan

No host changes are required to remove these controller-side restrictions.
