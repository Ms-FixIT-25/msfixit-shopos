#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
doc="$root/docs/PERFORMANCE_PROFILE.md"

test -s "$doc"
grep -Fq '`efficiency`' "$doc"
grep -Fq '`balanced`' "$doc"
grep -Fq '`performance`' "$doc"
grep -Fq 'sudo msfixit-hardware-report' "$doc"
grep -Fq '/var/log/msfixit-shopos/hardware-report.txt' "$doc"
grep -Fq 'does not overclock' "$doc"
grep -Fq 'schedutil' "$doc"

printf 'PASS: Raspberry Pi performance profile documentation.\n'
