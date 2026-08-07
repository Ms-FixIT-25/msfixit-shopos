#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="$root/image/package/etc/systemd/system/msfixit-hardware-report.service.d/README"

test -s "$readme"
grep -Fq 'idle I/O priority' "$readme"
grep -Fq 'systemctl start msfixit-hardware-report.service' "$readme"

printf 'PASS: hardware report scheduling guidance.\n'
