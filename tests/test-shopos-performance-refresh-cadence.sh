#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="$root/image/package/etc/systemd/system/msfixit-performance-profile.timer.d/README"

test -s "$readme"
grep -Fq 'not a high-frequency control loop' "$readme"
grep -Fq 'does not poll the CPU continuously' "$readme"

printf 'PASS: low-frequency performance profile refresh guidance.\n'
