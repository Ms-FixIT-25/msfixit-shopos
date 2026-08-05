#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/image/package/usr/share/msfixit-shopos/admin-console/public/index.php"
helper="$root/image/package/usr/local/sbin/msfixit-admin-action"
sudoers="$root/image/package/etc/sudoers.d/msfixit-admin-console"

php -l "$app"
bash -n "$helper"

grep -Fq "authenticated() && isset(\$_POST['action'])" "$app"
grep -Fq "hash_equals(csrfToken(), \$token)" "$app"
grep -Fq "sudo -n /usr/local/sbin/msfixit-admin-action" "$app"
grep -Fq "array_slice(\$lines, -200)" "$app"
grep -Fq "latest_backup" "$app"

grep -Fq "case \"\$action\" in" "$helper"
grep -Fq "cache-flush)" "$helper"
grep -Fq "service-restart)" "$helper"
grep -Fq "backup-create)" "$helper"
grep -Fq "logs)" "$helper"
grep -Fq "result=rejected" "$helper"
grep -Fq "[REDACTED]" "$helper"
grep -Fq "tail -n 200" "$helper"

if grep -Eq 'www-data ALL=\(root\) NOPASSWD: ALL' "$sudoers"; then
    echo "Unrestricted sudo rule detected." >&2
    exit 1
fi

grep -Fq "/usr/local/sbin/msfixit-admin-action cache-flush" "$sudoers"
grep -Fq "/usr/local/sbin/msfixit-admin-action service-restart nginx" "$sudoers"
grep -Fq "/usr/local/sbin/msfixit-admin-action backup-create" "$sudoers"
grep -Fq "/usr/local/sbin/msfixit-admin-action logs shopos" "$sudoers"

printf 'PASS: admin console Phase 2 allowlisted actions, audit logging, bounded logs and secret filtering checks.\n'
