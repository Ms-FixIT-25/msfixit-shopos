#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
path_unit="$root/image/package/etc/systemd/system/msfixit-performance-profile.path"
service="$root/image/package/etc/systemd/system/msfixit-performance-profile.service"
refresh="$root/image/package/etc/systemd/system/msfixit-performance-refresh.service"
timer="$root/image/package/etc/systemd/system/msfixit-performance-profile.timer"

test -s "$path_unit"
test -s "$service"
test -s "$refresh"
test -s "$timer"
grep -Fxq 'PathChanged=/etc/msfixit-shopos/performance.env' "$path_unit"
grep -Fxq 'Unit=msfixit-performance-refresh.service' "$path_unit"
grep -Fxq 'Type=oneshot' "$service"
if grep -Fq 'RemainAfterExit=yes' "$service"; then
    echo 'Performance profile service must remain restartable.' >&2
    exit 1
fi
grep -Fxq 'Before=msfixit-resource-budget.service msfixit-kiosk.service' "$service"
grep -Fxq 'ExecStart=/usr/local/sbin/msfixit-finalize-resource-budget' "$refresh"
grep -Fxq 'IOSchedulingClass=idle' "$refresh"
grep -Fxq 'OnUnitActiveSec=12h' "$timer"
grep -Fxq 'RandomizedDelaySec=15min' "$timer"
grep -Fxq 'Unit=msfixit-performance-refresh.service' "$timer"

printf 'PASS: profile changes reapply limits and refresh active services.\n'
