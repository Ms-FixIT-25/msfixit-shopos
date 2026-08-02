#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_version="0.1.0"
if [ -f "${root}/image/VERSION" ]; then
    default_version="$(tr -d '[:space:]' < "${root}/image/VERSION")"
fi
version="${SHOPOS_VERSION:-$default_version}"
cloudflared_version="${CLOUDFLARED_VERSION:-latest}"
source_dir="${root}/image/package"
output_dir="${root}/image/packages"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

command -v curl >/dev/null
command -v dpkg-deb >/dev/null

cp -a "${source_dir}/." "$stage/"
sed -i "s/@VERSION@/${version}/g" "$stage/DEBIAN/control"

install -d -m 0755 "$stage/usr/local/bin"

if [ "$cloudflared_version" = "latest" ]; then
    cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
else
    cloudflared_url="https://github.com/cloudflare/cloudflared/releases/download/${cloudflared_version}/cloudflared-linux-arm64"
fi

curl --fail --location --retry 5 --retry-all-errors \
    "$cloudflared_url" \
    --output "$stage/usr/local/bin/cloudflared"

curl --fail --location --retry 5 --retry-all-errors \
    https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    --output "$stage/usr/local/bin/wp"

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
    printf 'CLOUDFLARED_SOURCE=%s\n' "$cloudflared_url"
    printf 'BUILD_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sha256sum "$stage/usr/local/bin/cloudflared" "$stage/usr/local/bin/wp"
} > "$stage/usr/share/msfixit-shopos/build-info.txt"

rm -rf "$output_dir"
install -d -m 0755 "$output_dir"
dpkg-deb --root-owner-group --build "$stage" "$output_dir/msfixit-shopos_arm64.deb"
sha256sum "$output_dir/msfixit-shopos_arm64.deb" > "$output_dir/msfixit-shopos_arm64.deb.sha256"

echo "Built $output_dir/msfixit-shopos_arm64.deb"
