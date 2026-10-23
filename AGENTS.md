# Bastion: agent instructions

## Scope and source of truth

- Communicate with the owner in Russian.
- Bastion configures an Ubuntu Server private VPN through Ansible.
- Read [the OpenSpec index](openspec/README.md) and the relevant files in `openspec/specs/` before proposing or implementing behavior. These are target requirements, not evidence of implementation.
- Keep [design proposals and open questions](openspec/notes/design-and-open-questions.md) distinct from normative requirements. Update the affected specifications and notes after the owner makes architectural decisions; never silently promote a proposal into a requirement.
- [Historical research](openspec/notes/research.md) preserves the prior Ansible and upstream findings. Recheck relevant upstream facts before implementation. The previous project `/home/alejandro/go/src/ansible` is a read-only reference unless changes there are separately requested.
- The current scope is updating specifications and plans for Ubuntu + Ansible. Implementation and deployment are outside this request. Do not deploy, delete or alter a live server as part of this work.
- The retained NixOS implementation and archived checks are historical; they do not verify Ubuntu/Ansible. Do not claim Ubuntu provisioning, idempotence, VM or live-client checks have passed.
- The owner permits copying needed secrets from `/home/alejandro/go/src/ansible` during implementation. Keep that source read-only, transfer only needed values into the agreed encrypted storage, and never expose plaintext or copy the administrator's private SSH key to the VPS. Documentation work does not require copying secrets.
- Future behavior changes use `openspec/changes/`. A specification scenario is an acceptance criterion, not a completed test.

## Working conventions

- Use GitHub MCP first for remote repository metadata/files/diffs. State when unavailable or insufficient; use web fallback only for information it cannot provide. Verify current technical claims against primary documentation.
- The owner requested direct file editing without Serena for this migration. Prefix shell commands with `rtk` as instructed by `/home/alejandro/.codex/RTK.md` when available.
- Use the smallest readable implementation. Reuse Ansible modules, native Ubuntu services and existing tools; avoid speculative abstractions, dependencies, lifecycle frameworks, and configuration switches.
- Preserve boundary validation, error handling, secret isolation, and necessary synchronization. Nontrivial new logic needs a focused regression test.
- Classify implementation scope before delegation. Handle small changes directly; delegate broad security/networking work to one `tech_lead` owning research, implementation, tests, and review. Root must not duplicate its child work.
- For GitHub PR review, spawn one `github_pr_reviewer` with `fork_turns="none"`. For other agents default to `fork_turns="none"` and provide scope, constraints, acceptance criteria, checks, and applicable instructions. Use at most one implementation reviewer and reuse it for follow-up review.
- If implementing an OpenSpec change, use both `openspec-apply-change` (artifacts/tasks) and `task` (engineering workflow). Locate those skills first; if unavailable, state the limitation instead of silently substituting a partial workflow.
- Never include real secrets in examples, logs, Git, this document, or command arguments. Do not send Telegram messages during analysis without authorization.
