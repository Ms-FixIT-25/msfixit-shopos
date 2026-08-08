# Test hygiene and stale-assumption policy

ShopOS CI must distinguish a real product regression from a test that has become stale because repository structure, formatting, file layout, workflow identity or artifact provenance changed.

## Rules

- Tests should validate behavior, schema, permissions, signatures, hashes or structured syntax rather than formatting or line layout.
- Do not use a concrete unrelated repository file as the end marker of a `sed` range. Parse the real construct instead.
- Security tests for Python should prefer AST/structured inspection to broad single-line `grep` expressions when code formatting can change the match meaning.
- Workflows and executable tests must not pin historical Actions run IDs, artifact IDs or PR refs as current validation input.
- Pull-request workflows must check out and verify the current event SHA.
- QEMU and ARM64-QEMU image identity is a provenance contract: an intentional immutable digest/build reference is allowed only where the workflow first resolves the newest successful checksum-verified image according to repository policy. Historical fallback is not allowed.
- If a test fails after a refactor while the intended contract still holds, fix the test on the CI/test-harness branch; do not change product behavior merely to satisfy stale text matching.
- If the contract itself changed, update product and regression coverage in the appropriate product PR.

## Blocking versus warning

The hygiene audit blocks only known high-confidence stale-test anti-patterns such as historical Actions/artifact IDs in executable validation and fragile `sed` ranges anchored to concrete repository paths. Potential fixed commit/PR references are warnings because immutable provenance can be legitimate.

The hygiene gate is not permission to ignore a red test. A red result must still be classified as either a real product/harness defect or a stale-test defect with evidence before correction.
