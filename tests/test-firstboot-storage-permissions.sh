#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
firstboot="$root/image/package/usr/local/sbin/msfixit-firstboot"
brand_shop="$root/image/package/usr/local/sbin/msfixit-brand-shop"
nginx_site="$root/image/package/etc/nginx/sites-available/msfixit-shopos.conf"
wordpress_assets="$root/image/package/usr/share/msfixit-shopos/wordpress"

test -f "$firstboot"
test -f "$brand_shop"
test -f "$nginx_site"
bash -n "$firstboot"
bash -n "$brand_shop"

grep -Fq 'install -d -m 0711 "$data_dir"' "$firstboot"
grep -Fq 'install -d -o mysql -g mysql -m 0750 "$data_dir/mariadb"' "$firstboot"
grep -Fq 'install -d -o www-data -g www-data -m 0750 "$data_dir/wordpress"' "$firstboot"
grep -Fq 'install -d -o www-data -g www-data -m 0750 "$data_dir/wordpress/uploads"' "$firstboot"

chown_line="$(grep -nF 'chown -R mysql:mysql "$data_dir/mariadb"' "$firstboot" | head -n1 | cut -d: -f1)"
init_line="$(grep -nF 'mariadb-install-db --user=mysql --datadir="$data_dir/mariadb" --skip-test-db' "$firstboot" | head -n1 | cut -d: -f1)"

test -n "$chown_line"
test -n "$init_line"
if [ "$chown_line" -ge "$init_line" ]; then
    printf 'MariaDB ownership must be repaired before mariadb-install-db runs.\n' >&2
    exit 1
fi

grep -Fq 'include snippets/fastcgi-php.conf;' "$nginx_site"
if grep -Fq '        try_files $uri =404;' "$nginx_site"; then
    printf 'The PHP location must not duplicate try_files from snippets/fastcgi-php.conf.\n' >&2
    exit 1
fi

# WordPress must be able to traverse the configuration directory while secret
# files retain their stricter individual modes.
grep -Fq 'install -d -o root -g www-data -m 0750 "$config_dir"' "$brand_shop"
grep -Fq 'install -m 0640 -o root -g www-data' "$brand_shop"

# WP-CLI eval-file wraps source code before evaluation. A strict_types
# declaration in the source therefore cannot remain the first statement.
grep -Fq 'run_wp_eval_file()' "$brand_shop"
grep -Fq 'chown www-data:www-data "$sanitized_file"' "$brand_shop"
grep -Fq 'chmod 0600 "$sanitized_file"' "$brand_shop"

for provisioner in \
    msfixit-provision.php \
    msfixit-commerce-provision.php \
    msfixit-discovery-provision.php \
    msfixit-help-provision.php \
    msfixit-service-provision.php; do
    test -f "$wordpress_assets/$provisioner"
    grep -Fq "run_wp_eval_file \"\$wordpress_assets/$provisioner\"" "$brand_shop"
done

if grep -Eq '^[[:space:]]*run_wp eval-file ' "$brand_shop"; then
    printf 'Provisioning files must pass through the sanitized eval-file wrapper.\n' >&2
    exit 1
fi

fixture="$(mktemp)"
filtered="$(mktemp)"
trap 'rm -f "$fixture" "$filtered"' EXIT
cat > "$fixture" <<'EOF_FIXTURE'
<?php
/** comment */
declare(strict_types=1);
echo 'ok';
EOF_FIXTURE
awk '!/^[[:space:]]*declare\(strict_types=1\);[[:space:]]*$/' "$fixture" > "$filtered"
if grep -Fq 'declare(strict_types=1);' "$filtered"; then
    printf 'The eval-file sanitizer did not remove strict_types.\n' >&2
    exit 1
fi
grep -Fq "echo 'ok';" "$filtered"

printf 'PASS: first-boot ownership, Nginx PHP configuration and WP-CLI provisioning permissions are safe.\n'
