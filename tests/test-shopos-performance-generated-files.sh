#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="$root/image/package/etc/systemd/system/msfixit-performance-profile.service.d/README"

test -s "$readme"
grep -Fq '/etc/msfixit-shopos/performance.env' "$readme"

printf 'PASS: generated performance configuration guidance.\n'
