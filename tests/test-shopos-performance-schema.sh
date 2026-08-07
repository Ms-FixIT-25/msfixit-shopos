#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
schema="$root/image/package/etc/msfixit-shopos/performance-profile.schema"

test -s "$schema"
grep -Fxq 'SHOPOS_PERFORMANCE_PROFILE=efficiency|balanced|performance' "$schema"
grep -Fq 'SHOPOS_CPU_GOVERNOR=auto|' "$schema"
grep -Fxq 'SHOPOS_WIFI_POLICY=auto|enabled|disabled' "$schema"
grep -Fxq 'SHOPOS_BLUETOOTH_POLICY=auto|enabled|disabled' "$schema"

printf 'PASS: ShopOS performance profile schema.\n'
