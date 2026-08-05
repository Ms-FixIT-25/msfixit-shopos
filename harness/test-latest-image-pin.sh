#!/usr/bin/env bash
set -Eeuo pipefail

workflow="${1:-.github/workflows/validate-latest-image.yml}"

bash -n tests/prepare-qemu-image.sh
bash -n tests/run-qemu-smoke.sh

grep -Fq "SHOPOS_ARTIFACT_ID: '8932620732'" "$workflow"
grep -Fq "SHOPOS_ARTIFACT_SHA256: 1bad705f7bbbaa99279274b72dd778106b8445f3d95d66e61cf39a2faeffb818" "$workflow"
grep -Fq "SHOPOS_SOURCE_SHA: 5d7df3843469c864a3fb3534dd2ceca8c7feaa9f" "$workflow"
grep -Fq 'artifact_head_sha="$(gh api' "$workflow"
grep -Fq 'test "$artifact_head_sha" = "$SHOPOS_SOURCE_SHA"' "$workflow"
grep -Fq 'sha256sum --check --strict' "$workflow"
grep -Fq 'sha256sum --check msfixit-shopos-rpi4-usb.img.zst.sha256' "$workflow"
grep -Fq 'runs-on: ${{ matrix.runner }}' "$workflow"
grep -Fq 'runner: ubuntu-26.04' "$workflow"
grep -Fq 'runner: ubuntu-26.04-arm' "$workflow"

printf 'PASS: release-candidate harness pins artifact ID, ZIP digest, source commit and both runner architectures.\n'
