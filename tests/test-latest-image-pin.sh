#!/usr/bin/env bash
set -Eeuo pipefail

workflow="${1:-.github/workflows/validate-latest-image.yml}"

bash -n tests/prepare-qemu-image.sh
bash -n tests/run-qemu-smoke.sh

grep -Fq "SHOPOS_ARTIFACT_ID: '8925522931'" "$workflow"
grep -Fq "SHOPOS_ARTIFACT_SHA256: 4660d23de6e3fb8a08c79b525f6c9049310d4fd090abf19c6769ea44db8a813a" "$workflow"
grep -Fq "SHOPOS_SOURCE_SHA: d15bf379fc5519008faf3c11d3a1328a978466ab" "$workflow"
grep -Fq 'artifact_head_sha="$(gh api' "$workflow"
grep -Fq 'test "$artifact_head_sha" = "$SHOPOS_SOURCE_SHA"' "$workflow"
grep -Fq 'sha256sum --check --strict' "$workflow"
grep -Fq 'sha256sum --check msfixit-shopos-rpi4-usb.img.zst.sha256' "$workflow"
grep -Fq 'runs-on: ${{ matrix.runner }}' "$workflow"
grep -Fq 'runner: ubuntu-26.04' "$workflow"
grep -Fq 'runner: ubuntu-26.04-arm' "$workflow"

printf 'PASS: latest-image harness pins artifact ID, ZIP digest, source commit and both runner architectures.\n'
