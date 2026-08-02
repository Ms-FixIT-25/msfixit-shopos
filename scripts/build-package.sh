#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${SHOPOS_VERSION:-0.1.0}"
cloudflared_version="${CLOUDFLARED_VERSION:-2026.7.2}"
cloudflared_sha256="${CLOUDFLARED_SHA256:-405df476437e027fc6d18729a5a77155c0a33a6082aeee60a799a688f3052e66}"
wp_cli_version="${WP_CLI_VERSION:-2.12.0}"
wp_cli_sha256="${WP_CLI_SHA256:-ce34ddd838f7351d6759068d09793f26755463b4a4610a5a5c0a97b68220d85c}"
source_dir="${root}/image/package"
output_dir="${root}/image/packages"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

command -v curl >/dev/null
command -v dpkg-deb >/dev/null
command -v sha256sum >/dev/null

cp -a "${source_dir}/." "$stage/"
sed -i "s/@VERSION@/${version}/g" "$stage/DEBIAN/control"

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
    printf 'BUILD_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sha256sum "$stage/usr/local/bin/cloudflared" "$stage/usr/local/bin/wp"
} > "$stage/usr/share/msfixit-shopos/build-info.txt"

rm -rf "$output_dir"
install -d -m 0755 "$output_dir"
dpkg-deb --root-owner-group --build "$stage" "$output_dir/msfixit-shopos_arm64.deb"
sha256sum "$output_dir/msfixit-shopos_arm64.deb" > "$output_dir/msfixit-shopos_arm64.deb.sha256"

echo "Built $output_dir/msfixit-shopos_arm64.deb"
