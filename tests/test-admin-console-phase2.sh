#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/image/package/usr/share/msfixit-shopos/admin-console/public/index.php"
helper="$root/image/package/usr/local/sbin/msfixit-admin-action"
sudoers="$root/image/package/etc/sudoers.d/msfixit-admin-console"

php -l "$app"
bash -n "$helper"

assert_contains() {
    local needle="$1"
    local file="$2"
    if ! grep -Fq -- "$needle" "$file"; then
        printf 'Missing expected text in %s: %s\n' "$file" "$needle" >&2
        exit 1
    fi
}

assert_contains "authenticated() && isset(\$_POST['action'])" "$app"
assert_contains "hash_equals(csrfToken(), \$token)" "$app"
assert_contains "sudo -n /usr/local/sbin/msfixit-admin-action" "$app"
assert_contains "array_slice(\$lines, -200)" "$app"
assert_contains "latest_backup" "$app"

assert_contains 'case "$action" in' "$helper"
assert_contains "cache-flush)" "$helper"
assert_contains "service-restart)" "$helper"
assert_contains "backup-create)" "$helper"
assert_contains "logs)" "$helper"
assert_contains "log_result rejected" "$helper"
assert_contains "[REDACTED]" "$helper"
assert_contains "tail -n 200" "$helper"

if grep -Eq 'www-data ALL=\(root\) NOPASSWD: ALL' "$sudoers"; then
    echo "Unrestricted sudo rule detected." >&2
    exit 1
fi

assert_contains "/usr/local/sbin/msfixit-admin-action cache-flush" "$sudoers"
assert_contains "/usr/local/sbin/msfixit-admin-action service-restart nginx" "$sudoers"
assert_contains "/usr/local/sbin/msfixit-admin-action backup-create" "$sudoers"
assert_contains "/usr/local/sbin/msfixit-admin-action logs shopos" "$sudoers"

printf 'PASS: admin console Phase 2 allowlisted actions, audit logging, bounded logs and secret filtering checks.\n'
