#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C
export TZ=UTC

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_version="0.1.0"
if [ -f "${root}/image/VERSION" ]; then
    default_version="$(tr -d '[:space:]' < "${root}/image/VERSION")"
fi
version="${SHOPOS_VERSION:-$default_version}"
cloudflared_version="${CLOUDFLARED_VERSION:-2026.7.2}"
cloudflared_sha256="${CLOUDFLARED_SHA256:-405df476437e027fc6d18729a5a77155c0a33a6082aeee60a799a688f3052e66}"
wp_cli_version="${WP_CLI_VERSION:-2.12.0}"
wp_cli_sha256="${WP_CLI_SHA256:-ce34ddd838f7351d6759068d09793f26755463b4a4610a5a5c0a97b68220d85c}"
wordpress_version="${WORDPRESS_VERSION:-7.0.2}"
woocommerce_version="${WOOCOMMERCE_VERSION:-10.9.4}"
woocommerce_sha256="${WOOCOMMERCE_SHA256:-6e58fc3ba9b18d1c9aee6b0227d3c3c09e4fe2c1332823bd2e0ac54ffcff64a9}"
redis_cache_version="${REDIS_CACHE_VERSION:-2.8.0}"
storefront_version="${STOREFRONT_VERSION:-4.6.2}"
brand_sha256="${MSFIXIT_BRAND_SHA256:-7a5769e7e58adf6074c50854a5e6cb36861607e7edac1e1feb1b62384d1928de}"
source_dir="${root}/image/package"
output_dir="${root}/image/packages"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

source_date_epoch="${SOURCE_DATE_EPOCH:-}"
if [ -z "$source_date_epoch" ]; then
    source_date_epoch="$(git -C "$root" log -1 --format=%ct 2>/dev/null || true)"
fi
[[ "$source_date_epoch" =~ ^[0-9]+$ ]] || {
    echo 'SOURCE_DATE_EPOCH must be an integer Unix timestamp or resolvable from the source commit.' >&2
    exit 2
}
export SOURCE_DATE_EPOCH="$source_date_epoch"
build_utc="$(date -u --date="@${SOURCE_DATE_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)"

command -v base64 >/dev/null
command -v curl >/dev/null
command -v date >/dev/null
command -v dpkg-deb >/dev/null
command -v git >/dev/null
command -v sha1sum >/dev/null
command -v sha256sum >/dev/null
command -v touch >/dev/null
command -v unzip >/dev/null

cp -a "${source_dir}/." "$stage/"
sed -i "s/@VERSION@/${version}/g" "$stage/DEBIAN/control"

brand_b64="$stage/usr/share/msfixit-shopos/branding/msfixit-brand-full.webp.b64"
brand_file="$stage/usr/share/msfixit-shopos/branding/msfixit-brand-full.webp"
base64 --decode "$brand_b64" > "$brand_file"
rm -f "$brand_b64"
printf '%s  %s\n' "$brand_sha256" "$brand_file" | sha256sum --check --strict
chmod 0644 "$brand_file"

install -d -m 0755 \
    "$stage/usr/local/bin" \
    "$stage/usr/local/lib/msfixit-shopos" \
    "$stage/usr/lib/msfixit-shopos"

cloudflared_url="https://github.com/cloudflare/cloudflared/releases/download/${cloudflared_version}/cloudflared-linux-arm64"
wp_cli_url="https://github.com/wp-cli/wp-cli/releases/download/v${wp_cli_version}/wp-cli-${wp_cli_version}.phar"

curl --fail --location --retry 5 --retry-all-errors \
    "$cloudflared_url" \
    --output "$stage/usr/local/bin/cloudflared"

curl --fail --location --retry 5 --retry-all-errors \
    "$wp_cli_url" \
    --output "$stage/usr/local/lib/msfixit-shopos/wp-cli.phar"

printf '%s  %s\n' "$cloudflared_sha256" "$stage/usr/local/bin/cloudflared" | sha256sum --check --strict
printf '%s  %s\n' "$wp_cli_sha256" "$stage/usr/local/lib/msfixit-shopos/wp-cli.phar" | sha256sum --check --strict

WORDPRESS_VERSION="$wordpress_version" \
WOOCOMMERCE_VERSION="$woocommerce_version" \
WOOCOMMERCE_SHA256="$woocommerce_sha256" \
REDIS_CACHE_VERSION="$redis_cache_version" \
STOREFRONT_VERSION="$storefront_version" \
    bash "${root}/scripts/fetch-vendor-assets.sh" "$stage"

chmod 0755 \
    "$stage/DEBIAN/postinst" \
    "$stage/etc/update-motd.d/10-msfixit-shopos" \
    "$stage/usr/local/bin/cloudflared" \
    "$stage/usr/local/bin/wp" \
    "$stage/usr/local/bin/shopos-version" \
    "$stage/usr/local/lib/msfixit-shopos/wp-cli.phar" \
    "$stage/usr/local/sbin/msfixit-firstboot" \
    "$stage/usr/local/sbin/msfixit-firstboot-progress" \
    "$stage/usr/local/sbin/msfixit-boot-state" \
    "$stage/usr/local/sbin/msfixit-boot-console" \
    "$stage/usr/local/sbin/msfixit-first-login-init" \
    "$stage/usr/local/sbin/msfixit-brand-shop" \
    "$stage/usr/local/sbin/msfixit-cloudflared-run" \
    "$stage/usr/local/sbin/msfixit-catalog-init" \
    "$stage/usr/local/sbin/msfixit-catalog" \
    "$stage/usr/local/sbin/msfixit-office-init" \
    "$stage/usr/local/sbin/msfixit-office" \
    "$stage/usr/local/sbin/msfixit-office-worker" \
    "$stage/usr/local/sbin/msfixit-office-dunning" \
    "$stage/usr/local/sbin/msfixit-office-print" \
    "$stage/usr/local/sbin/msfixit-compliance" \
    "$stage/usr/local/sbin/msfixit-compliance-worker" \
    "$stage/usr/local/sbin/msfixit-tax-decision" \
    "$stage/usr/local/sbin/msfixit-also-init" \
    "$stage/usr/local/sbin/msfixit-also" \
    "$stage/usr/local/sbin/msfixit-also-content" \
    "$stage/usr/local/sbin/msfixit-also-content-sync" \
    "$stage/usr/local/sbin/msfixit-discovery" \
    "$stage/usr/local/sbin/msfixit-partners-init" \
    "$stage/usr/local/sbin/msfixit-partners" \
    "$stage/usr/local/sbin/msfixit-apply-config" \
    "$stage/usr/local/sbin/msfixit-health" \
    "$stage/usr/local/sbin/msfixit-backup" \
    "$stage/usr/local/sbin/msfixit-status"
chmod 0644 \
    "$stage/usr/lib/msfixit-shopos/shopos-app-install.py" \
    "$stage/usr/lib/msfixit-shopos/validate-shopos-app.py"

install -d -m 0755 "$stage/usr/share/msfixit-shopos"
{
    printf 'SHOPOS_VERSION=%s\n' "$version"
    printf 'WORDPRESS_VERSION=%s\n' "$wordpress_version"
    printf 'WORDPRESS_LOCALE=de_DE\n'
    printf 'WORDPRESS_SOURCE=https://de.wordpress.org/wordpress-%s-de_DE.zip\n' "$wordpress_version"
    printf 'WOOCOMMERCE_VERSION=%s\n' "$woocommerce_version"
    printf 'WOOCOMMERCE_SOURCE=https://downloads.wordpress.org/plugin/woocommerce.%s.zip\n' "$woocommerce_version"
    printf 'WOOCOMMERCE_SHA256=%s\n' "$woocommerce_sha256"
    printf 'REDIS_CACHE_VERSION=%s\n' "$redis_cache_version"
    printf 'REDIS_CACHE_SOURCE=https://downloads.wordpress.org/plugin/redis-cache.%s.zip\n' "$redis_cache_version"
    printf 'STOREFRONT_VERSION=%s\n' "$storefront_version"
    printf 'STOREFRONT_SOURCE=https://downloads.wordpress.org/theme/storefront.%s.zip\n' "$storefront_version"
    printf 'CLOUDFLARED_VERSION=%s\n' "$cloudflared_version"
    printf 'CLOUDFLARED_SOURCE=%s\n' "$cloudflared_url"
    printf 'CLOUDFLARED_SHA256=%s\n' "$cloudflared_sha256"
    printf 'WP_CLI_VERSION=%s\n' "$wp_cli_version"
    printf 'WP_CLI_SOURCE=%s\n' "$wp_cli_url"
    printf 'WP_CLI_SHA256=%s\n' "$wp_cli_sha256"
    printf 'MSFIXIT_BRAND_SHA256=%s\n' "$brand_sha256"
    printf 'CATALOG_SCHEMA_VERSION=1\n'
    printf 'OFFICE_SCHEMA_VERSION=2\n'
    printf 'COMPLIANCE_SCHEMA_VERSION=1\n'
    printf 'ALSO_PILOT_SCHEMA_VERSION=1\n'
    printf 'ALSO_CONTENT_SCHEMA_VERSION=1\n'
    printf 'DISCOVERY_SCHEMA_VERSION=1\n'
    printf 'PARTNER_SCHEMA_VERSION=1\n'
    printf 'HELP_CENTER_VERSION=1\n'
    printf 'SERVICE_PORTAL_VERSION=1\n'
    printf 'BOOT_EXPERIENCE_VERSION=1\n'
    printf 'BUILD_EPOCH=%s\n' "$SOURCE_DATE_EPOCH"
    printf '%s=%s\n' BUILD_UTC "$build_utc"
    (
        cd "$stage"
        sha256sum \
            usr/local/bin/cloudflared \
            usr/local/bin/wp \
            usr/local/bin/shopos-version \
            usr/local/lib/msfixit-shopos/wp-cli.phar \
            usr/local/sbin/msfixit-firstboot \
            usr/local/sbin/msfixit-firstboot-progress \
            usr/local/sbin/msfixit-boot-state \
            usr/local/sbin/msfixit-boot-console \
            usr/local/sbin/msfixit-first-login-init \
            usr/local/sbin/msfixit-brand-shop \
            usr/local/sbin/msfixit-cloudflared-run \
            usr/local/sbin/msfixit-tax-decision \
            usr/local/sbin/msfixit-also \
            usr/local/sbin/msfixit-also-content \
            usr/local/sbin/msfixit-also-content-sync \
            usr/local/sbin/msfixit-discovery \
            usr/local/sbin/msfixit-partners-init \
            usr/local/sbin/msfixit-partners \
            usr/lib/msfixit-shopos/shopos-app-install.py \
            usr/lib/msfixit-shopos/validate-shopos-app.py \
            usr/share/msfixit-shopos/branding/msfixit-brand-full.webp \
            usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.plymouth \
            usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.script \
            usr/share/msfixit-shopos/vendor/SHA256SUMS \
            usr/share/msfixit-shopos/catalog/schema.sql \
            usr/share/msfixit-shopos/catalog/guards.sql \
            usr/share/msfixit-shopos/office/schema.sql \
            usr/share/msfixit-shopos/office/operational.sql \
            usr/share/msfixit-shopos/office/migrations.sql \
            usr/share/msfixit-shopos/office/office-lib.php \
            usr/share/msfixit-shopos/compliance/schema.sql \
            usr/share/msfixit-shopos/compliance/guards.sql \
            usr/share/msfixit-shopos/compliance/strict-guards.sql \
            usr/share/msfixit-shopos/compliance/strict-migrations.sql \
            usr/share/msfixit-shopos/compliance/tax-decision-migrations.sql \
            usr/share/msfixit-shopos/compliance/renderer-guards.sql \
            usr/share/msfixit-shopos/also/schema.sql \
            usr/share/msfixit-shopos/also/content.sql \
            usr/share/msfixit-shopos/also/content-guards.sql \
            usr/share/msfixit-shopos/also/also.env.example \
            usr/share/msfixit-shopos/discovery/discovery.env.example \
            usr/share/msfixit-shopos/discovery/discovery-lib.php \
            usr/share/msfixit-shopos/partners/schema.sql \
            usr/share/msfixit-shopos/wordpress/msfixit-compliance.php \
            usr/share/msfixit-shopos/wordpress/msfixit-compliance-runtime.php \
            usr/share/msfixit-shopos/wordpress/msfixit-at-pilot.php \
            usr/share/msfixit-shopos/wordpress/msfixit-also-draft.php \
            usr/share/msfixit-shopos/wordpress/msfixit-also-content.php \
            usr/share/msfixit-shopos/wordpress/msfixit-also-content-apply.php \
            usr/share/msfixit-shopos/wordpress/msfixit-discovery.php \
            usr/share/msfixit-shopos/wordpress/msfixit-discovery-provision.php \
            usr/share/msfixit-shopos/wordpress/msfixit-discovery-cli.php \
            usr/share/msfixit-shopos/wordpress/msfixit-help-center.php \
            usr/share/msfixit-shopos/wordpress/msfixit-help-provision.php \
            usr/share/msfixit-shopos/wordpress/msfixit-service-requests.php \
            usr/share/msfixit-shopos/wordpress/msfixit-service-provision.php \
            usr/share/msfixit-shopos/wordpress/assets/msfixit-discovery.js \
            usr/share/msfixit-shopos/wordpress/assets/msfixit-discovery.css \
            usr/share/msfixit-shopos/wordpress/assets/msfixit-help-center.css \
            usr/share/msfixit-shopos/wordpress/assets/msfixit-service-requests.css
    )
} > "$stage/usr/share/msfixit-shopos/build-info.txt"

cat "$stage/usr/share/msfixit-shopos/vendor/SHA256SUMS"

find "$stage" -exec touch --no-dereference --date="@${SOURCE_DATE_EPOCH}" {} +

rm -rf "$output_dir"
install -d -m 0755 "$output_dir"
dpkg-deb --root-owner-group --build "$stage" "$output_dir/msfixit-shopos_arm64.deb"
sha256sum "$output_dir/msfixit-shopos_arm64.deb" > "$output_dir/msfixit-shopos_arm64.deb.sha256"

echo "Built $output_dir/msfixit-shopos_arm64.deb (SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH)"
