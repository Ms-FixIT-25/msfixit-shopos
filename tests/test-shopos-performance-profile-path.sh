#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
path_unit="$root/image/package/etc/systemd/system/msfixit-performance-profile.path"
service="$root/image/package/etc/systemd/system/msfixit-performance-profile.service"

test -s "$path_unit"
test -s "$service"
grep -Fxq 'PathChanged=/etc/msfixit-shopos/performance.env' "$path_unit"
grep -Fxq 'Unit=msfixit-performance-profile.service' "$path_unit"
grep -Fxq 'RemainAfterExit=yes' "$service"
grep -Fxq 'Before=msfixit-resource-budget.service msfixit-kiosk.service' "$service"

printf 'PASS: performance profile changes are reapplied through systemd.\n'
