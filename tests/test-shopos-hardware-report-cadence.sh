#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="$root/image/package/etc/systemd/system/msfixit-hardware-report.timer.d/README"

test -s "$readme"
grep -Fq 'intentionally infrequent' "$readme"
grep -Fq 'Run the report manually' "$readme"

printf 'PASS: low-impact hardware report cadence guidance.\n'
