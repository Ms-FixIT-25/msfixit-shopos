# ShopOS Agent Handoff Protocol

This file defines how coding agents may continue ShopOS work when a human/interactive development session stops. Repository-wide rules in `.github/copilot-instructions.md` remain mandatory.

## Core principle
Agents may continue **well-defined work**, not invent product direction. CI and reproducible system validation are the authority.

## Mandatory startup sequence
Before editing anything:
1. Read `.github/copilot-instructions.md` and this file.
2. Read the assigned issue and linked PR/workflow evidence.
3. Classify the task as exactly one of:
   - `product`
   - `test-harness`
   - `documentation/policy`
   - `needs-human-decision`
4. Confirm the allowed scope and forbidden scope from the issue.
5. For system validation, identify the newest successfully built Raspberry Pi image with verified checksum/integrity. Record build/run, artifact identity and digest when available.
6. Post/update status as `AGENT_WORKING` before substantive implementation when the platform permits progress comments.

## Handoff state machine
Use these states in issue/PR progress updates:

- `READY_FOR_AGENT` — task is sufficiently specified and safe for autonomous work.
- `AGENT_WORKING` — implementation or analysis is actively in progress.
- `WAITING_FOR_CI` — implementation is complete for the current iteration and CI/system validation is running.
- `BLOCKED_NEEDS_HUMAN` — an explicit stop condition was reached.
- `READY_FOR_HUMAN_REVIEW` — implementation and required available validation are complete; a human should review the result.

Do not claim completion while required CI is still running or failing.

## Branch and PR boundaries
- Never commit directly to `main`.
- Never merge to `main`.
- Never enable auto-merge.
- Use focused branches and Draft PRs.
- Product code changes and temporary QEMU/VM harness changes must never share a branch or PR.
- Documentation/policy work should remain separate when it is not required for a product fix.
- Do not add opportunistic refactors or cleanup outside the assigned scope.

## Failure handling loop
For an unambiguous CI or system-test failure:
1. Capture the failing workflow/job/step and relevant error.
2. Determine whether the root cause is product or harness.
3. If classification differs from the current branch, stop and create/report the need for the correctly scoped branch/PR rather than crossing the boundary.
4. Implement the smallest correct fix.
5. Add or update a regression test where practical.
6. Run the narrowest useful validation first, then required broader validation.
7. Report what failed, root cause, what changed, current workflow state and next concrete step.
8. Repeat only while the next fix is unambiguous and remains in scope.

Never weaken, skip, delete or bypass a meaningful test merely to make CI green.

## Image provenance and QEMU
Normal QEMU and ARM64-QEMU validation must:
- use only the newest successfully built Raspberry Pi image that has passed checksum/integrity verification;
- record the image/build/artifact identity used;
- fail closed if provenance cannot be established;
- never silently fall back to an older image;
- keep normal and ARM64 results independently visible.

A newly built image does not become the validation source merely because it is newer; it must first satisfy the repository's successful-build and integrity requirements.

## Progress checkpoints
When comments/status updates are available, report a concise checkpoint after:
- taking ownership/classifying the task;
- a meaningful implementation milestone;
- each relevant build, QEMU or ARM64-QEMU result;
- discovering a failure/root cause;
- applying a corrective fix;
- reaching a human-decision blocker;
- reaching `READY_FOR_HUMAN_REVIEW`.

A checkpoint should contain:
- state;
- completed work;
- running/passed/failed validation;
- new success or resolved problem;
- current blocker, if any;
- next concrete action.

## Mandatory stop conditions
Set `BLOCKED_NEEDS_HUMAN` and do not guess when:
- requirements or architecture are materially ambiguous;
- multiple security-sensitive solutions have meaningful tradeoffs;
- destructive operations, data migration or compatibility breaks require a product decision;
- a merge conflict requires interpreting competing intent;
- the required fix crosses the declared product/harness boundary;
- the newest checksum-verified image cannot be determined;
- credentials, secrets, signing material or privileged external access would be required;
- tests reveal a broader product-design problem rather than a bounded defect;
- proceeding would require disabling a security or integrity control.

Explain the decision needed and provide evidence/options where possible.

## Product-fix rules
Product branches may change production behavior. They must:
- explain the root cause;
- keep the fix minimal;
- include regression coverage where practical;
- preserve ARM64 compatibility;
- establish required service/file ownership and permissions explicitly;
- keep provisioning deterministic and idempotent where possible.

WP-CLI fixes are product work. Do not solve WP-CLI or production permission defects inside a VM/QEMU harness branch.

## Test-harness rules
Harness branches exist to validate the product, not change it. They must:
- avoid production behavior changes;
- avoid masking real product failures;
- preserve image checksum/provenance checks;
- keep architecture-specific emulation behavior explicit;
- remain disposable when the temporary harness is no longer required.

## Admin Console gate
Do not begin or expand substantive Admin Console work until both normal QEMU and ARM64-QEMU system tests have demonstrated repeated stable green runs on qualifying checksum-verified images. If this gate is not satisfied, report the gate status instead of implementing Admin Console features.

## Definition of READY_FOR_HUMAN_REVIEW
Use `READY_FOR_HUMAN_REVIEW` only when:
- the change remains within assigned scope;
- regression coverage is present where practical;
- required available CI has passed, or any unavailable validation is explicitly documented;
- system tests used qualifying image provenance;
- no known unresolved failure is being hidden;
- the Draft PR clearly states what changed, why, validation performed and remaining limitations.

Human review remains required. Agents do not merge ShopOS changes to `main`.