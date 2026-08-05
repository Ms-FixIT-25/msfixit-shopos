#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

required_files=(
    image/package/usr/local/sbin/msfixit-firstboot
    image/package/usr/local/sbin/msfixit-admin-action
    image/package/usr/local/sbin/msfixit-admin-console-init
    image/package/usr/share/msfixit-shopos/admin-console/public/index.php
    image/package/etc/nginx/sites-available/msfixit-shopos.conf
    image/package/etc/nginx/snippets/msfixit-admin-console.conf
    image/package/etc/systemd/system/msfixit-admin-console-init.service
)

for file in "${required_files[@]}"; do
    test -s "$file" || fail "required release file missing or empty: $file"
done

# Every shipped shell entry point must parse cleanly.
while IFS= read -r -d '' file; do
    bash -n "$file" || fail "shell syntax error: $file"
done < <(find image/package/usr/local -type f -print0)

# Every shipped PHP file must parse cleanly.
while IFS= read -r -d '' file; do
    php -l "$file" >/dev/null || fail "PHP syntax error: $file"
done < <(find image/package -type f -name '*.php' -print0)

firstboot=image/package/usr/local/sbin/msfixit-firstboot
admin_action=image/package/usr/local/sbin/msfixit-admin-action
admin_php=image/package/usr/share/msfixit-shopos/admin-console/public/index.php
admin_nginx=image/package/etc/nginx/snippets/msfixit-admin-console.conf

# Provisioning and persistent-storage safety invariants.
grep -Fq 'install -d -m 0711 "$data_dir"' "$firstboot" || fail '/data must remain traversable'
grep -Fq 'install -d -o mysql -g mysql -m 0750 "$data_dir/mariadb"' "$firstboot" || fail 'MariaDB directory ownership invariant missing'
grep -Fq 'install -d -o www-data -g www-data -m 0750 "$data_dir/wordpress"' "$firstboot" || fail 'WordPress directory ownership invariant missing'
grep -Fq 'run_wp_eval_file()' "$firstboot" || fail 'WP-CLI eval-file sanitizer missing'
grep -Fq 'chmod 0600 "$sanitized_file"' "$firstboot" || fail 'sanitized WP-CLI file must be private'

# Admin console security baseline.
grep -Fq "session_regenerate_id(true);" "$admin_php" || fail 'session rotation missing'
grep -Fq "hash_equals(csrfToken(), \$token)" "$admin_php" || fail 'CSRF validation missing'
grep -Fq "Content-Security-Policy:" "$admin_php" || fail 'CSP header missing'
grep -Fq "X-Frame-Options: DENY" "$admin_php" || fail 'clickjacking protection missing'
grep -Fq "Cache-Control: no-store" "$admin_php" || fail 'sensitive responses must not be cached'
grep -Fq "escapeshellarg" "$admin_php" || fail 'privileged action arguments must be escaped'
! grep -REn "(password|secret|token|api[_-]?key)[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]" image/package/usr/share/msfixit-shopos/admin-console --include='*.php' || fail 'possible hard-coded secret in admin console'

# Privileged helper must remain an explicit allowlist with restrictive defaults.
grep -Fq 'set -Eeuo pipefail' "$admin_action" || fail 'strict shell mode missing from privileged helper'
grep -Fq 'umask 077' "$admin_action" || fail 'restrictive umask missing from privileged helper'
grep -Fq '*) log_result rejected; exit 2 ;;' "$admin_action" || fail 'fail-closed action default missing'
grep -Fq "options='nosuid,nodev,noexec'" "$admin_action" || fail 'safe removable-media mount options missing'
grep -Fq "sed -E 's/(password|passwd|secret|token|api[_-]?key)=" "$admin_action" || fail 'log redaction missing'

# Admin endpoint must remain LAN/localhost only.
grep -Fq 'allow 127.0.0.1;' "$admin_nginx" || fail 'localhost allow rule missing'
grep -Fq 'allow 10.0.0.0/8;' "$admin_nginx" || fail 'private IPv4 allow rule missing'
grep -Fq 'deny all;' "$admin_nginx" || fail 'default deny missing'

# Prevent accidental production release behavior outside main.
grep -Fq "github.ref == 'refs/heads/main'" .github/workflows/build-image.yml || fail 'release publishing must remain main-only'

printf 'PASS: ShopOS release-candidate syntax, provisioning, permissions, admin security, device safety and release isolation are intact.\n'
