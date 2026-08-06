#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kiosk="$root/image/package/usr/local/sbin/msfixit-kiosk-session"
service="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
budget="$root/image/package/usr/local/sbin/msfixit-apply-resource-budget"
thermal="$root/image/package/usr/local/sbin/msfixit-thermal-check"
timer="$root/image/package/etc/systemd/system/msfixit-thermal-check.timer"
mariadb="$root/image/package/etc/mysql/mariadb.conf.d/60-shopos-pi-budget.cnf"
postinst="$root/image/package/DEBIAN/postinst"

bash -n "$kiosk"
bash -n "$budget"
bash -n "$thermal"

grep -Fq -- '--disable-background-networking' "$kiosk"
grep -Fq -- '--renderer-process-limit=3' "$kiosk"
grep -Fq 'CPUQuota=150%' "$service"
grep -Fq 'MemoryMax=896M' "$service"
grep -Fq 'pm = ondemand' "$budget"
grep -Fq 'pm.max_children = 8' "$budget"
grep -Fq 'maxmemory 192mb' "$budget"
grep -Fq 'innodb_buffer_pool_size=192M' "$mariadb"
grep -Fq 'max_connections=40' "$mariadb"
grep -Fq 'degrees >= 78' "$thermal"
grep -Fq 'OnUnitActiveSec=2min' "$timer"
grep -Fq 'systemctl enable msfixit-thermal-check.timer' "$postinst"

if grep -Eq 'over_voltage|arm_freq|force_turbo' "$root/image/package" -R; then
    echo 'ShopOS must not overclock Raspberry Pi hardware.' >&2
    exit 1
fi

printf 'PASS: ShopOS applies bounded kiosk, PHP, Redis, MariaDB and thermal-monitoring defaults.\n'
