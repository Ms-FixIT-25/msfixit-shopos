#!/usr/bin/env bash
set -Eeuo pipefail

workflow="${1:-.github/workflows/validate-latest-image.yml}"

bash -n tests/prepare-qemu-image.sh
bash -n tests/run-qemu-smoke.sh

grep -Fq "SHOPOS_ARTIFACT_ID: '8929701044'" "$workflow"
grep -Fq "SHOPOS_ARTIFACT_SHA256: e245e520a6ca5212242f74f881dad9dae455782df18bce11b3fd7011576cc3de" "$workflow"
grep -Fq "SHOPOS_SOURCE_SHA: 0d15ea1de82d84917192974c2d316e10e29f39be" "$workflow"
grep -Fq 'artifact_head_sha="$(gh api' "$workflow"
grep -Fq 'test "$artifact_head_sha" = "$SHOPOS_SOURCE_SHA"' "$workflow"
grep -Fq 'sha256sum --check --strict' "$workflow"
grep -Fq 'sha256sum --check msfixit-shopos-rpi4-usb.img.zst.sha256' "$workflow"
grep -Fq 'runs-on: ${{ matrix.runner }}' "$workflow"
grep -Fq 'runner: ubuntu-26.04' "$workflow"
grep -Fq 'runner: ubuntu-26.04-arm' "$workflow"

printf 'PASS: release-candidate harness pins artifact ID, ZIP digest, source commit and both runner architectures.\n'
