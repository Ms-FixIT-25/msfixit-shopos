#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="$root/image/package/usr/local/sbin/msfixit-apply-performance-profile"
report="$root/image/package/usr/local/sbin/msfixit-hardware-report"
example="$root/image/package/etc/msfixit-shopos/performance.env.example"

bash -n "$profile"
bash -n "$report"
test -s "$example"

grep -Fq 'SHOPOS_PERFORMANCE_PROFILE=balanced' "$example"
grep -Fq 'efficiency|balanced|performance' "$profile"
grep -Fq 'MemTotal:' "$profile"
grep -Fq 'mem_mib < 3000' "$profile"
grep -Fq 'mem_mib < 6000' "$profile"
grep -Fq 'innodb_buffer_pool_size=${mariadb_pool}' "$profile"
grep -Fq 'maxmemory ${redis_memory}' "$profile"
grep -Fq 'pm.max_children = ${php_children}' "$profile"
grep -Fq 'MemoryHigh=${kiosk_high}' "$profile"
grep -Fq 'MemoryMax=${kiosk_max}' "$profile"
grep -Fq 'scaling_available_governors' "$profile"
grep -Fq 'schedutil' "$profile"
grep -Fq 'systemctl enable fstrim.timer' "$profile"
grep -Fq 'Applied ${SHOPOS_PERFORMANCE_PROFILE} profile' "$profile"

if grep -Eq 'force_turbo|over_voltage|arm_freq=' "$profile" "$example"; then
    echo 'Adaptive appliance profiles must not overclock or change core voltage.' >&2
    exit 1
fi

if grep -Eq 'echo performance.*scaling_governor|SHOPOS_CPU_GOVERNOR=performance' "$profile" "$example"; then
    echo 'The default profile must not pin the CPU at maximum frequency.' >&2
    exit 1
fi

printf 'PASS: adaptive RAM-tiered Raspberry Pi appliance profile contract.\n'
