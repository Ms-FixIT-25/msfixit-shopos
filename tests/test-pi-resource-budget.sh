#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kiosk="$root/image/package/usr/local/sbin/msfixit-kiosk-session"
service="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
brand_service="$root/image/package/etc/systemd/system/msfixit-brand-shop.service"
budget="$root/image/package/usr/local/sbin/msfixit-apply-resource-budget"
finalizer="$root/image/package/usr/local/sbin/msfixit-finalize-resource-budget"
budget_service="$root/image/package/etc/systemd/system/msfixit-resource-budget.service"
hw_service="$root/image/package/etc/systemd/system/msfixit-hardware-manager.service"
hw_thermal="$root/image/package/usr/lib/msfixit-shopos/hardware_manager/thermal.py"
hw_state="$root/image/package/usr/lib/msfixit-shopos/hardware_manager/state.py"
mariadb="$root/image/package/etc/mysql/mariadb.conf.d/zz-shopos-pi-budget.cnf"
old_mariadb="$root/image/package/etc/mysql/mariadb.conf.d/60-shopos-pi-budget.cnf"
postinst="$root/image/package/DEBIAN/postinst"

bash -n "$kiosk"
bash -n "$budget"
bash -n "$finalizer"
python3 -m py_compile "$hw_thermal" "$hw_state"

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
grep -Fq 'After=msfixit-firstboot.service msfixit-resource-budget.service' "$brand_service"
if grep -Fq 'network-online.target' "$brand_service"; then
    echo 'Local branding must remain available without Internet or Wi-Fi.' >&2
    exit 1
fi

grep -Fq 'return cls(60.0, 70.0, 78.0, 83.0)' "$hw_thermal"
grep -Fq 'rise_samples: int = 3' "$hw_thermal"
grep -Fq 'emergency_samples: int = 4' "$hw_thermal"
grep -Fq 'emergency_min_seconds: int = 120' "$hw_thermal"
grep -Fq 'shutdown_enabled: bool = False' "$hw_thermal"
grep -Fq 'sample_interval_seconds: int = 30' "$hw_state"
grep -Fq 'persist_interval_seconds: int = 300' "$hw_state"
grep -Fq 'CPUQuota=20%' "$hw_service"
grep -Fq 'MemoryMax=96M' "$hw_service"
grep -Fq 'systemctl enable msfixit-hardware-manager.service' "$postinst"
if grep -Fq 'msfixit-thermal-check' "$postinst"; then
    echo 'Legacy thermal timer must not be enabled alongside Hardware Manager.' >&2
    exit 1
fi

if grep -Eq 'over_voltage|arm_freq|force_turbo' "$root/image/package" -R; then
    echo 'ShopOS must not overclock Raspberry Pi hardware.' >&2
    exit 1
fi

printf 'PASS: ShopOS keeps bounded Pi workloads and one lightweight hysteretic Hardware Manager thermal monitor.\n'
