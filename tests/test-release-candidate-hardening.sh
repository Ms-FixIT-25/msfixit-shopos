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
    image/package/usr/local/sbin/msfixit-brand-shop
    image/package/usr/local/sbin/msfixit-admin-action
    image/package/usr/local/sbin/msfixit-admin-console-init
    image/package/usr/local/bin/shopos-version
    image/package/usr/share/msfixit-shopos/admin-console/public/index.php
    image/package/etc/nginx/sites-available/msfixit-shopos.conf
    image/package/etc/nginx/snippets/msfixit-admin-console.conf
    image/package/etc/systemd/system/msfixit-admin-console-init.service
)

for file in "${required_files[@]}"; do
    test -s "$file" || fail "required release file missing or empty: $file"
done

# Validate executable entry points with the interpreter declared by their
# shebang. /usr/local intentionally contains both shell and PHP commands.
while IFS= read -r -d '' file; do
    first_line="$(head -n1 "$file")"
    case "$first_line" in
        '#!'*bash*|'#!'*'/sh')
            bash -n "$file" || fail "shell syntax error: $file"
            ;;
        '#!'*php*)
            php -l "$file" >/dev/null || fail "PHP syntax error: $file"
            ;;
        '#!'*)
            fail "unsupported executable interpreter in $file: $first_line"
            ;;
        *)
            ;;
    esac
done < <(find image/package/usr/local -type f -print0)

# Every shipped PHP source file must parse cleanly, including web assets and
# PHP entry points that are not executable in the source tree.
while IFS= read -r -d '' file; do
    php -l "$file" >/dev/null || fail "PHP syntax error: $file"
done < <(find image/package -type f -name '*.php' -print0)

firstboot=image/package/usr/local/sbin/msfixit-firstboot
brand_shop=image/package/usr/local/sbin/msfixit-brand-shop
admin_action=image/package/usr/local/sbin/msfixit-admin-action
admin_php=image/package/usr/share/msfixit-shopos/admin-console/public/index.php
admin_nginx=image/package/etc/nginx/snippets/msfixit-admin-console.conf
version_cmd=image/package/usr/local/bin/shopos-version

# First-boot persistent-storage safety invariants.
grep -Fq 'install -d -m 0711 "$data_dir"' "$firstboot" || fail '/data must remain traversable'
grep -Fq 'install -d -o mysql -g mysql -m 0750 "$data_dir/mariadb"' "$firstboot" || fail 'MariaDB directory ownership invariant missing'
grep -Fq 'install -d -o www-data -g www-data -m 0750 "$data_dir/wordpress"' "$firstboot" || fail 'WordPress directory ownership invariant missing'

# WP-CLI product provisioning belongs to msfixit-brand-shop. Keep the helper,
# ownership, private mode and every provisioning entry point under regression.
grep -Fq 'run_wp_eval_file()' "$brand_shop" || fail 'WP-CLI eval-file sanitizer missing'
grep -Fq "awk '!/^[[:space:]]*declare\\(strict_types=1\\);[[:space:]]*$/'" "$brand_shop" || fail 'strict_types sanitizer missing'
grep -Fq 'chown www-data:www-data "$sanitized_file"' "$brand_shop" || fail 'sanitized WP-CLI file owner invariant missing'
grep -Fq 'chmod 0600 "$sanitized_file"' "$brand_shop" || fail 'sanitized WP-CLI file must be private'
grep -Fq 'install -d -o root -g www-data -m 0750 "$config_dir"' "$brand_shop" || fail 'ShopOS config directory traversal invariant missing'
for provisioner in \
    msfixit-provision.php \
    msfixit-commerce-provision.php \
    msfixit-discovery-provision.php \
    msfixit-help-provision.php \
    msfixit-service-provision.php; do
    grep -Fq "run_wp_eval_file \"\$wordpress_assets/$provisioner\"" "$brand_shop" \
        || fail "provisioner does not use safe WP-CLI wrapper: $provisioner"
done

# Execute the exact sanitizer expression against a representative fixture.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cat > "$tmp_dir/source.php" <<'PHP'
<?php
declare(strict_types=1);

echo "sparkles";
PHP
awk '!/^[[:space:]]*declare\(strict_types=1\);[[:space:]]*$/' \
    "$tmp_dir/source.php" > "$tmp_dir/sanitized.php"
! grep -Fq 'declare(strict_types=1);' "$tmp_dir/sanitized.php" || fail 'strict_types survived sanitizer fixture'
grep -Fq 'echo "sparkles";' "$tmp_dir/sanitized.php" || fail 'sanitizer removed executable payload'
php -l "$tmp_dir/sanitized.php" >/dev/null || fail 'sanitized PHP fixture is invalid'

# Admin console security baseline.
grep -Fq 'session_regenerate_id(true);' "$admin_php" || fail 'session rotation missing'
grep -Fq 'hash_equals(csrfToken(), $token)' "$admin_php" || fail 'CSRF validation missing'
grep -Fq 'Content-Security-Policy:' "$admin_php" || fail 'CSP header missing'
grep -Fq 'X-Frame-Options: DENY' "$admin_php" || fail 'clickjacking protection missing'
grep -Fq 'Cache-Control: no-store' "$admin_php" || fail 'sensitive responses must not be cached'
grep -Fq 'escapeshellarg' "$admin_php" || fail 'privileged action arguments must be escaped'
! grep -REn "(password|secret|token|api[_-]?key)[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]" \
    image/package/usr/share/msfixit-shopos/admin-console --include='*.php' \
    || fail 'possible hard-coded secret in admin console'

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

# Community Easter egg is opt-in and must never alter normal version output.
normal_version_output="$(bash "$version_cmd")"
unicorn_output="$(bash "$version_cmd" --unicorn)"
[[ "$normal_version_output" != *'UNICORN_MODE'* ]] || fail 'Easter egg leaked into normal version output'
[[ "$unicorn_output" == *'UNICORN_MODE=stable'* ]] || fail 'opt-in unicorn marker missing'
[[ "$unicorn_output" == *'No unicorns were harmed'* ]] || fail 'community Easter egg signature missing'

# Prevent accidental production release behavior outside main.
grep -Fq "github.ref == 'refs/heads/main'" .github/workflows/build-image.yml || fail 'release publishing must remain main-only'

printf 'PASS: ShopOS release-candidate syntax, provisioning, permissions, admin security, device safety, community details and release isolation are intact.\n'
