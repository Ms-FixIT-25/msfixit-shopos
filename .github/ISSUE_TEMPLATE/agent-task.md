---
name: Agent-safe ShopOS task
about: Hand off a bounded product, test-harness, or policy task to a coding agent
title: "[agent] "
labels: []
assignees: []
---

## Task class
<!-- Choose exactly one: product | test-harness | documentation/policy -->

## Goal
<!-- One concrete outcome. -->

## Current evidence
<!-- Relevant PR, workflow/run, logs, image build/artifact/digest, error message. -->

## Allowed scope
<!-- Exact files/components/behavior the agent may change. -->

## Forbidden scope
- Do not merge to `main`.
- Do not enable auto-merge.
- Do not mix product and temporary test-harness changes.
- Do not weaken, skip, delete or bypass meaningful tests.
- Do not silently fall back to an older or unverified Raspberry Pi image.
- Do not perform unrelated refactors/cleanup.

## Required validation
<!-- Unit/regression/build/QEMU/ARM64-QEMU as applicable. -->

## Stop and request human decision when
- requirements or architecture are ambiguous;
- a security-sensitive choice has multiple plausible solutions;
- destructive/migration/compatibility-breaking behavior is required;
- a merge conflict requires interpreting intent;
- the fix crosses the declared product/harness boundary;
- the newest successfully built checksum-verified image cannot be established;
- a security/integrity control would need to be disabled.

## Progress reporting
Use the states defined in `AGENTS.md` and post checkpoints for meaningful progress and each relevant CI/system-test result.

## Acceptance criteria
<!-- Objective conditions that make the task complete. -->

## Agent state
`READY_FOR_AGENT`
