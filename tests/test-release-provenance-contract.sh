#!/usr/bin/env bash
set -euo pipefail

release_workflow=".github/workflows/production-release.yml"
[[ -f "$release_workflow" ]] || { echo "missing production release workflow" >&2; exit 1; }

# Release publication must remain downstream of validation, exact image build and QEMU boot.
grep -q 'needs:.*validate' "$release_workflow" || { echo "release workflow must depend on validation" >&2; exit 1; }
grep -q 'qemu' "$release_workflow" || { echo "release workflow must include QEMU validation" >&2; exit 1; }

# Published artifacts must carry checksum/evidence/provenance material rather than an unbound image alone.
grep -Eqi 'sha256|checksum' "$release_workflow" || { echo "release workflow must verify/publish checksums" >&2; exit 1; }
grep -Eqi 'evidence|provenance|attestation' "$release_workflow" || { echo "release workflow must retain validation evidence/provenance" >&2; exit 1; }

# Stable/latest must never be silently promoted by this contract.
if grep -Eq -- '--latest([ =]|$)|make_latest:[[:space:]]*true' "$release_workflow"; then
  echo "automatic latest promotion is forbidden by release provenance contract" >&2
  exit 1
fi

echo "release provenance contract: PASS"
