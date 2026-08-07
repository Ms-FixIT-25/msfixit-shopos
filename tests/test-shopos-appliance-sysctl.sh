#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/image/package/etc/sysctl.d/60-shopos-appliance.conf"

test -s "$config"
grep -Fxq 'vm.swappiness=10' "$config"
grep -Fxq 'vm.vfs_cache_pressure=75' "$config"
grep -Fxq 'vm.dirty_background_ratio=5' "$config"
grep -Fxq 'vm.dirty_ratio=15' "$config"

if grep -Eq 'vm\.dirty_(background_)?ratio=([3-9][0-9]|[1-9][0-9]{2,})' "$config"; then
    echo 'Dirty writeback ratios are too large for a Raspberry Pi appliance.' >&2
    exit 1
fi

printf 'PASS: conservative Raspberry Pi VM and writeback tuning.\n'
