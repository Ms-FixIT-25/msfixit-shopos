#!/usr/bin/env bash
set -Eeuo pipefail

workflow="${1:-.github/workflows/validate-latest-image.yml}"

bash -n tests/prepare-qemu-image.sh
bash -n tests/run-qemu-smoke.sh

grep -Fq "SHOPOS_ARTIFACT_ID: '8943848343'" "$workflow"
grep -Fq "SHOPOS_ARTIFACT_SHA256: e37a02234ebf12f905681ff39787959f500130046f18b3e2dfccf1e5758959ee" "$workflow"
grep -Fq "SHOPOS_SOURCE_SHA: 5a799d79dba7015fd8a18f974a4cc6079ae24dfa" "$workflow"
grep -Fq 'artifact_head_sha="$(gh api' "$workflow"
grep -Fq 'test "$artifact_head_sha" = "$SHOPOS_SOURCE_SHA"' "$workflow"
grep -Fq 'sha256sum --check --strict' "$workflow"
grep -Fq -- "-name '*.img.zst.sha256'" "$workflow"
grep -Fq -- "-name '*.img.xz.sha256'" "$workflow"
grep -Fq -- "-name '*.img.gz.sha256'" "$workflow"
grep -Fq 'candidate_entry="$(awk' "$workflow"
grep -Fq 'candidate_entry="${candidate_entry#\*}"' "$workflow"
grep -Fq 'candidate_archive="$candidate_dir/$candidate_entry"' "$workflow"
grep -Fq 'candidate_archive="$candidate_dir/$(basename "${candidate_checksum%.sha256}")"' "$workflow"
grep -Fq '*.img.zst|*.img.xz|*.img.gz' "$workflow"
grep -Fq '[[ "$candidate_sha" =~ ^[0-9a-fA-F]{64}$ ]]' "$workflow"
grep -Fq 'test "$valid_pairs" -eq 1' "$workflow"
grep -Fq 'printf '\''%s  %s\n'\'' "$expected_image_sha" "$image_archive" | sha256sum --check --strict' "$workflow"
grep -Fq '*.img.zst) unzstd --no-progress' "$workflow"
grep -Fq '*.img.xz) xz --decompress --stdout' "$workflow"
grep -Fq '*.img.gz) gzip --decompress --stdout' "$workflow"
grep -Fq 'xz-utils gzip' "$workflow"
grep -Fq 'runs-on: ${{ matrix.runner }}' "$workflow"
grep -Fq 'runner: ubuntu-26.04' "$workflow"
grep -Fq 'runner: ubuntu-26.04-arm' "$workflow"

printf 'PASS: release-candidate harness pins provenance and resolves one valid checksummed compressed image pair on both runner architectures.\n'
