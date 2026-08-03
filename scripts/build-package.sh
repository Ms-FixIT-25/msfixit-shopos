#!/usr/bin/env bash
set -Eeuo pipefail

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
brand_sha256="${MSFIXIT_BRAND_SHA256:-7a5769e7e58adf6074c50854a5e6cb36861607e7edac1e1feb1b62384d1928de}"
source_dir="${root}/image/package"
output_dir="${root}/image/packages"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

command -v base64 >/dev/null
command -v curl >/dev/null
command -v dpkg-deb >/dev/null
command -v sha256sum >/dev/null

cp -a "${source_dir}/." "$stage/"
sed -i "s/@VERSION@/${version}/g" "$stage/DEBIAN/control"

brand_b64="$stage/usr/share/msfixit-shopos/branding/msfixit-brand-full.webp.b64"
brand_file="$stage/usr/share/msfixit-shopos/branding/msfixit-brand-full.webp"
base64 --decode "$brand_b64" > "$brand_file"
rm -f "$brand_b64"
printf '%s  %s\n' "$brand_sha256" "$brand_file" | sha256sum --check --strict
chmod 0644 "$brand_file"

install -d -m 0755 "$stage/usr/local/bin"

cloudflared_url="https://github.com/cloudflare/cloudflared/releases/download/${cloudflared_version}/cloudflared-linux-arm64"
wp_cli_url="https://github.com/wp-cli/wp-cli/releases/download/v${wp_cli_version}/wp-cli-${wp_cli_version}.phar"

curl --fail --location --retry 5 --retry-all-errors \
    "$cloudflared_url" \
    --output "$stage/usr/local/bin/cloudflared"

curl --fail --location --retry 5 --retry-all-errors \
    "$wp_cli_url" \
    --output "$stage/usr/local/bin/wp"

printf '%s  %s\n' "$cloudflared_sha256" "$stage/usr/local/bin/cloudflared" | sha256sum --check --strict
printf '%s  %s\n' "$wp_cli_sha256" "$stage/usr/local/bin/wp" | sha256sum --check --strict

chmod 0755 \
    "$stage/DEBIAN/postinst" \
    "$stage/usr/local/bin/cloudflared" \
    "$stage/usr/local/bin/wp" \
    "$stage/usr/local/sbin/msfixit-firstboot" \
    "$stage/usr/local/sbin/msfixit-brand-shop" \
    "$stage/usr/local/sbin/msfixit-catalog-init" \
    "$stage/usr/local/sbin/msfixit-catalog" \
    "$stage/usr/local/sbin/msfixit-office-init" \
    "$stage/usr/local/sbin/msfixit-office" \
    "$stage/usr/local/sbin/msfixit-office-worker" \
    "$stage/usr/local/sbin/msfixit-office-dunning" \
    "$stage/usr/local/sbin/msfixit-office-print" \
    "$stage/usr/local/sbin/msfixit-apply-config" \
    "$stage/usr/local/sbin/msfixit-health" \
    "$stage/usr/local/sbin/msfixit-backup" \
    "$stage/usr/local/sbin/msfixit-status"

install -d -m 0755 "$stage/usr/share/msfixit-shopos"
{
    printf 'SHOPOS_VERSION=%s\n' "$version"
    printf 'CLOUDFLARED_VERSION=%s\n' "$cloudflared_version"
    printf 'CLOUDFLARED_SOURCE=%s\n' "$cloudflared_url"
    printf 'CLOUDFLARED_SHA256=%s\n' "$cloudflared_sha256"
    printf 'WP_CLI_VERSION=%s\n' "$wp_cli_version"
    printf 'WP_CLI_SOURCE=%s\n' "$wp_cli_url"
    printf 'WP_CLI_SHA256=%s\n' "$wp_cli_sha256"
    printf 'MSFIXIT_BRAND_SHA256=%s\n' "$brand_sha256"
    printf 'CATALOG_SCHEMA_VERSION=1\n'
    printf 'OFFICE_SCHEMA_VERSION=1\n'
    printf 'BUILD_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sha256sum \
        "$stage/usr/local/bin/cloudflared" \
        "$stage/usr/local/bin/wp" \
        "$brand_file" \
        "$stage/usr/share/msfixit-shopos/catalog/schema.sql" \
        "$stage/usr/share/msfixit-shopos/catalog/guards.sql" \
        "$stage/usr/share/msfixit-shopos/office/schema.sql" \
        "$stage/usr/share/msfixit-shopos/office/operational.sql" \
        "$stage/usr/share/msfixit-shopos/office/office-lib.php"
} > "$stage/usr/share/msfixit-shopos/build-info.txt"

rm -rf "$output_dir"
install -d -m 0755 "$output_dir"
dpkg-deb --root-owner-group --build "$stage" "$output_dir/msfixit-shopos_arm64.deb"
sha256sum "$output_dir/msfixit-shopos_arm64.deb" > "$output_dir/msfixit-shopos_arm64.deb.sha256"

echo "Built $output_dir/msfixit-shopos_arm64.deb"
