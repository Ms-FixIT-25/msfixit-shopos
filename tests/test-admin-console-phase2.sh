#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "Phase 2 regression test failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

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
        return 1
    fi
}

assert_contains "authenticated() && isset(\$_POST['action'])" "$app"
assert_contains "hash_equals(csrfToken(), \$token)" "$app"
assert_contains "\$argv = ['sudo', '-n', '/usr/local/sbin/msfixit-admin-action', \$action];" "$app"
assert_contains "return runCommand(\$argv," "$app"
# runCommand now reads argv-based proc_open streams directly. Bound both
# stdout and stderr in memory instead of relying on the obsolete shell/line
# array slicing implementation.
assert_contains 'if (strlen($stdout) > 2097152) $stdout = substr($stdout, -2097152);' "$app"
assert_contains 'if (strlen($stderr) > 2097152) $stderr = substr($stderr, -2097152);' "$app"
assert_contains "latest_backup" "$app"

if grep -Fq "shell_exec('sudo -n /usr/local/sbin/msfixit-admin-action" "$app"; then
    echo "Admin actions must use argv-based proc_open execution, not a shell command string." >&2
    exit 1
fi

assert_contains 'case "$action" in' "$helper"
assert_contains "cache-flush)" "$helper"
assert_contains "service-restart)" "$helper"
assert_contains "backup-create)" "$helper"
assert_contains "logs)" "$helper"
assert_contains '[ -n "$SEEN_AT" ] || return 1' "$helper"
assert_contains "log_result rejected" "$helper"
assert_contains "[REDACTED]" "$helper"
assert_contains "tail -n 200" "$helper"

if grep -Eq '^www-data ALL=\(root\) NOPASSWD:[[:space:]]+ALL([[:space:]]|$)' "$sudoers"; then
    echo "Unrestricted sudo rule detected." >&2
    exit 1
fi

assert_contains "/usr/local/sbin/msfixit-admin-action cache-flush" "$sudoers"
assert_contains "/usr/local/sbin/msfixit-admin-action service-restart nginx" "$sudoers"
assert_contains "/usr/local/sbin/msfixit-admin-action backup-create" "$sudoers"
assert_contains "/usr/local/sbin/msfixit-admin-action logs shopos" "$sudoers"

printf 'PASS: admin console Phase 2 uses argv-based allowlisted actions, validates timestamped device requests, bounds proc_open streams, audits actions, bounds logs and filters secrets.\n'
