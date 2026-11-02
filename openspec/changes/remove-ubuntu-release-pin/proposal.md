# Proposal

## Why

The owner requires Ubuntu without tying provisioning to one Ubuntu release.
The current preflight and platform role reject every release except 26.04.

## What Changes

- Keep Ubuntu distribution checks, removing exact-release checks in both entry points.
- Verify acceptance of different Ubuntu releases and continued rejection of other distributions.
- Describe 26.04 as historical verification context, not an installation requirement.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `server-platform`: provisioning must not require a particular Ubuntu release.

## Impact

Preflight, platform assertion, focused tests, installation documentation and
platform requirements. No package, dependency or VM image changes; no deployment.
