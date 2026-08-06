#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kiosk="$root/image/package/usr/local/sbin/msfixit-kiosk-session"
service="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
brand_service="$root/image/package/etc/systemd/system/msfixit-brand-shop.service"
budget="$root/image/package/usr/local/sbin/msfixit-apply-resource-budget"
finalizer="$root/image/package/usr/local/sbin/msfixit-finalize-resource-budget"
budget_service="$root/image/package/etc/systemd/system/msfixit-resource-budget.service"
thermal="$root/image/package/usr/local/sbin/msfixit-thermal-check"
timer="$root/image/package/etc/systemd/system/msfixit-thermal-check.timer"
mariadb="$root/image/package/etc/mysql/mariadb.conf.d/zz-shopos-pi-budget.cnf"
old_mariadb="$root/image/package/etc/mysql/mariadb.conf.d/60-shopos-pi-budget.cnf"
postinst="$root/image/package/DEBIAN/postinst"

bash -n "$kiosk"
bash -n "$budget"
bash -n "$finalizer"
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
test ! -e "$old_mariadb"

grep -Fq '/usr/local/sbin/msfixit-apply-resource-budget' "$finalizer"
grep -Fq 'restart_if_active mariadb.service' "$finalizer"
grep -Fq 'restart_if_active redis-server.service' "$finalizer"
grep -Fq "'php*-fpm.service'" "$finalizer"
grep -Fq 'After=local-fs.target msfixit-firstboot.service' "$budget_service"
grep -Fq 'Before=msfixit-brand-shop.service' "$budget_service"
grep -Fq 'ExecStart=/usr/local/sbin/msfixit-finalize-resource-budget' "$budget_service"
grep -Fq 'RemainAfterExit=yes' "$budget_service"
grep -Fq 'systemctl enable msfixit-resource-budget.service' "$postinst"
grep -Fq 'Requires=msfixit-resource-budget.service' "$brand_service"
grep -Fq 'After=network-online.target msfixit-firstboot.service msfixit-resource-budget.service' "$brand_service"

grep -Fq 'degrees >= 78' "$thermal"
grep -Fq 'OnUnitActiveSec=2min' "$timer"
grep -Fq 'systemctl enable msfixit-thermal-check.timer' "$postinst"

if grep -Eq 'over_voltage|arm_freq|force_turbo' "$root/image/package" -R; then
    echo 'ShopOS must not overclock Raspberry Pi hardware.' >&2
    exit 1
fi

printf 'PASS: ShopOS readiness requires active bounded kiosk, PHP, Redis and final-precedence MariaDB limits.\n'
