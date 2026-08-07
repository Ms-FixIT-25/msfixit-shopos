#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="$root/image/package/etc/msfixit-shopos/README-performance.txt"

test -s "$readme"
grep -Fq 'Profiles: efficiency, balanced, performance' "$readme"
grep -Fq 'sudo systemctl start msfixit-performance-profile.service' "$readme"
grep -Fq 'sudo msfixit-hardware-report' "$readme"
grep -Fq 'does not overclock' "$readme"

printf 'PASS: installed performance profile help.\n'
