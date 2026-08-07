#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
health="$root/image/package/usr/local/sbin/msfixit-health"
office_init="$root/image/package/usr/local/sbin/msfixit-office-init"

bash -n "$health"
bash -n "$office_init"

mapfile -t required_timers < <(
    awk '/systemctl enable \\/ {capture=1; next} capture && /systemctl start \\/ {capture=0} capture {gsub(/\\/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 ~ /^msfixit-.*\.timer$/) print $0}' "$office_init"
)

for timer in "${required_timers[@]}"; do
    grep -Fq "$timer" "$health" || {
        echo "Health check does not monitor required office/compliance timer: $timer" >&2
        exit 1
    }
done

grep -Fq 'msfixit-compliance-worker.timer' "$health"
grep -Fq 'failed+=("$timer")' "$health"

printf 'PASS: every office/compliance timer enabled by initialization is covered by ShopOS health monitoring.\n'
