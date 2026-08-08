# GitHub Copilot instructions for Ms. FixIT ShopOS

## Purpose
ShopOS is a Raspberry-Pi-oriented product. Changes must preserve a production-quality, reproducible and testable ARM64 system image.

When continuing work from an assigned issue, read and follow root `AGENTS.md` in addition to this file. `AGENTS.md` defines the handoff state machine, progress checkpoints and mandatory stop conditions.

## Safety and branch policy
- Never merge changes to `main` automatically.
- Never enable auto-merge.
- Work through focused branches and draft pull requests.
- Keep product fixes separate from temporary test-harness changes.
- Do not mix unrelated cleanup or refactors into a bug-fix PR.
- If a merge conflict exists, report it explicitly rather than resolving it speculatively.

## Product versus test harness
- Product fixes belong on dedicated product branches and must include regression coverage when practical.
- VM/QEMU test infrastructure belongs on a dedicated harness branch/PR and must not alter production behaviour merely to make a test pass.
- A temporary VM test harness must remain isolated from product code.

## Image provenance
- Normal QEMU and ARM64-QEMU system validation must use only the newest successfully built Raspberry Pi image that has passed checksum/integrity verification.
- Do not silently fall back to an older image when the newest valid image fails.
- Record the image/build identity used by a system test so failures are reproducible.

## CI and validation
- Treat CI, build, integrity, QEMU and ARM64-QEMU results as authoritative; do not assume generated code is correct because it compiles locally.
- For an unambiguous failure, identify the root cause and make the smallest correct fix on the appropriate product or harness branch.
- Add or update regression tests for corrected defects where practical.
- Do not weaken, skip or bypass tests merely to obtain a green workflow.
- Preserve checksum verification and fail closed when image provenance cannot be established.
- Report new successes, running steps, failures, fixed problems and the next concrete action when investigating CI.

## Raspberry Pi / ARM64 requirements
- ARM64 is a first-class target.
- Avoid architecture-specific assumptions unless explicitly guarded and tested.
- Shell scripts must be non-interactive where used in image builds/provisioning, fail predictably, and use safe quoting.
- File ownership and permissions required by services must be established explicitly during provisioning rather than relying on incidental defaults.

## WordPress / WP-CLI provisioning
- WP-CLI provisioning must be deterministic and idempotent where possible.
- Required ownership and permissions must be set explicitly.
- Do not paper over permission failures with globally writable permissions.
- Product provisioning fixes must remain separate from QEMU/VM harness work.

## Admin console gate
- Do not expand the Admin Console based on an unstable system baseline.
- Before substantive Admin Console follow-up, normal QEMU and ARM64-QEMU system tests must be repeatedly stable and green on checksum-verified images.

## Code quality and security
- Prefer minimal, reviewable changes.
- Never commit secrets, tokens, credentials or private keys.
- Validate external input and quote shell variables.
- Prefer explicit failure over silent corruption or an unverifiable image.
- Preserve existing security checks unless a change is justified and covered by tests.

## Pull-request expectations
Every substantive PR should make clear:
1. what problem it solves;
2. whether it changes product code or test harness only;
3. what regression coverage was added or updated;
4. which build/system validations are required;
5. any known limitation or follow-up.

Copilot should review against these rules and flag violations rather than proposing shortcuts around them.
