#!/usr/bin/env bash
set -Eeuo pipefail

workflow="${1:-.github/workflows/validate-latest-image.yml}"

bash -n tests/prepare-qemu-image.sh
bash -n tests/run-qemu-smoke.sh

grep -Fq "SHOPOS_ARTIFACT_ID: '8919865233'" "$workflow"
grep -Fq "SHOPOS_ARTIFACT_SHA256: dd4d684f1059d4d2b2c561780735c271574d273d3c31eb5b6c2e9966027662a5" "$workflow"
grep -Fq "SHOPOS_SOURCE_SHA: 615c0e7ee4941d5f34c8fcac9b051b1e16443871" "$workflow"
grep -Fq 'artifact_head_sha="$(gh api' "$workflow"
grep -Fq 'test "$artifact_head_sha" = "$SHOPOS_SOURCE_SHA"' "$workflow"
grep -Fq 'sha256sum --check --strict' "$workflow"
grep -Fq 'sha256sum --check msfixit-shopos-rpi4-usb.img.zst.sha256' "$workflow"
grep -Fq 'runs-on: ${{ matrix.runner }}' "$workflow"
grep -Fq 'runner: ubuntu-26.04' "$workflow"
grep -Fq 'runner: ubuntu-26.04-arm' "$workflow"

printf 'PASS: latest-image harness pins artifact ID, ZIP digest, source commit and both runner architectures.\n'
