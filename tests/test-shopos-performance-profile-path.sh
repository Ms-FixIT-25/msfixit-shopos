#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
path_unit="$root/image/package/etc/systemd/system/msfixit-performance-profile.path"
service="$root/image/package/etc/systemd/system/msfixit-performance-profile.service"
timer="$root/image/package/etc/systemd/system/msfixit-performance-profile.timer"

test -s "$path_unit"
test -s "$service"
test -s "$timer"
grep -Fxq 'PathChanged=/etc/msfixit-shopos/performance.env' "$path_unit"
grep -Fxq 'Unit=msfixit-performance-profile.service' "$path_unit"
grep -Fxq 'Type=oneshot' "$service"
if grep -Fq 'RemainAfterExit=yes' "$service"; then
    echo 'Performance profile service must be restartable by its path and timer units.' >&2
    exit 1
fi
grep -Fxq 'Before=msfixit-resource-budget.service msfixit-kiosk.service' "$service"
grep -Fxq 'IOSchedulingClass=idle' "$service"
grep -Fxq 'OnUnitActiveSec=12h' "$timer"
grep -Fxq 'RandomizedDelaySec=15min' "$timer"

printf 'PASS: performance profile changes are repeatably reapplied through systemd.\n'
