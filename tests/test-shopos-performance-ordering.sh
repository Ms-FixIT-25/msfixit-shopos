#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dropin="$root/image/package/etc/systemd/system/msfixit-performance-profile.service.d/10-resource-budget.conf"

test -s "$dropin"
grep -Fxq 'Before=msfixit-resource-budget.service' "$dropin"

printf 'PASS: adaptive profile is applied before resource finalization.\n'
