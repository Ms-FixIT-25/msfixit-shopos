#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
service="$root/image/package/etc/systemd/system/msfixit-performance-profile.service"
path_unit="$root/image/package/etc/systemd/system/msfixit-performance-profile.path"
timer="$root/image/package/etc/systemd/system/msfixit-performance-profile.timer"
report_service="$root/image/package/etc/systemd/system/msfixit-hardware-report.service"
report_timer="$root/image/package/etc/systemd/system/msfixit-hardware-report.timer"

for unit in "$service" "$path_unit" "$timer" "$report_service" "$report_timer"; do
    test -s "$unit"
done

if find "$root/image/package/etc/systemd/system" -path '*/multi-user.target.wants/*' -type f -print -quit | grep -q .; then
    echo 'Systemd enable links must not be packaged as plain text files.' >&2
    exit 1
fi

grep -Fxq 'WantedBy=multi-user.target' "$service"
grep -Fxq 'WantedBy=multi-user.target' "$path_unit"
grep -Fxq 'WantedBy=timers.target' "$timer"
grep -Fxq 'WantedBy=timers.target' "$report_timer"

printf 'PASS: ShopOS performance services are packaged as real units.\n'
