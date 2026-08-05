#!/usr/bin/env bash
set -Eeuo pipefail

workflow="${1:-.github/workflows/validate-latest-image.yml}"

bash -n tests/prepare-qemu-image.sh
bash -n tests/run-qemu-smoke.sh

grep -Fq "SHOPOS_ARTIFACT_ID: '8926275454'" "$workflow"
grep -Fq "SHOPOS_ARTIFACT_SHA256: ee8f979943f9e9b8505c24b6b81cea20198fcdd24eeb4f478cf3041dcea792b6" "$workflow"
grep -Fq "SHOPOS_SOURCE_SHA: af720e356a3c1467937cd158f265bbd71f5cdd17" "$workflow"
grep -Fq 'artifact_head_sha="$(gh api' "$workflow"
grep -Fq 'test "$artifact_head_sha" = "$SHOPOS_SOURCE_SHA"' "$workflow"
grep -Fq 'sha256sum --check --strict' "$workflow"
grep -Fq 'sha256sum --check msfixit-shopos-rpi4-usb.img.zst.sha256' "$workflow"
grep -Fq 'runs-on: ${{ matrix.runner }}' "$workflow"
grep -Fq 'runner: ubuntu-26.04' "$workflow"
grep -Fq 'runner: ubuntu-26.04-arm' "$workflow"

printf 'PASS: latest-image harness pins artifact ID, ZIP digest, source commit and both runner architectures.\n'
