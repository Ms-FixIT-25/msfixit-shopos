#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report="$root/image/package/usr/local/sbin/msfixit-hardware-report"
service="$root/image/package/etc/systemd/system/msfixit-hardware-report.service"
timer="$root/image/package/etc/systemd/system/msfixit-hardware-report.timer"

bash -n "$report"
test -s "$service"
test -s "$timer"

grep -Fq 'vcgencmd get_throttled' "$report"
grep -Fq '/sys/devices/system/cpu/cpufreq/policy' "$report"
grep -Fq '/proc/pressure/' "$report"
grep -Fq 'lsblk -e7' "$report"
grep -Fq 'lsusb -t' "$report"
grep -Fq 'fstrim --dry-run' "$report"
grep -Fq 'systemctl show' "$report"
grep -Fq 'Recent power, thermal and storage warnings' "$report"
grep -Fq 'ConditionVirtualization=!container' "$service"
grep -Fq 'IOSchedulingClass=idle' "$service"
grep -Fq 'CPUWeight=5' "$service"
grep -Fq 'OnUnitActiveSec=6h' "$timer"
grep -Fq 'RandomizedDelaySec=20min' "$timer"

if grep -Eiq '(password|token|secret|credential|wp-config|database\.env)' "$report"; then
    echo 'Hardware report must not collect application credentials or secrets.' >&2
    exit 1
fi

printf 'PASS: low-impact Raspberry Pi hardware and efficiency reporting contract.\n'
