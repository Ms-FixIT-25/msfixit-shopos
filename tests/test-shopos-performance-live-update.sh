#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="$root/image/package/etc/systemd/system/msfixit-performance-profile.path.d/README"

test -s "$readme"
grep -Fq '/etc/msfixit-shopos/performance.env' "$readme"
grep -Fq 'one-shot reapplication' "$readme"
grep -Fq 'resource-budget finalizer' "$readme"

printf 'PASS: live performance profile update guidance.\n'
