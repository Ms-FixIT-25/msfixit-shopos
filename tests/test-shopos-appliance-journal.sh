#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/image/package/etc/systemd/journald.conf.d/60-shopos-appliance.conf"

test -s "$config"
grep -Fxq 'SystemMaxUse=128M' "$config"
grep -Fxq 'SystemKeepFree=256M' "$config"
grep -Fxq 'RuntimeMaxUse=64M' "$config"
grep -Fxq 'MaxRetentionSec=14day' "$config"
grep -Fxq 'Compress=yes' "$config"
grep -Fxq 'RateLimitIntervalSec=30s' "$config"
grep -Fxq 'RateLimitBurst=1000' "$config"

printf 'PASS: bounded journal storage and write-amplification policy.\n'
