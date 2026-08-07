#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 PACKAGE_STAGE" >&2
    exit 2
fi

readonly stage="$1"
readonly vendor_dir="$stage/usr/share/msfixit-shopos/vendor"
readonly wordpress_version=7.0.2
readonly woocommerce_version=10.9.4
readonly woocommerce_sha256=6e58fc3ba9b18d1c9aee6b0227d3c3c09e4fe2c1332823bd2e0ac54ffcff64a9
readonly redis_cache_version=2.8.0
readonly storefront_version=4.6.2

install -d -m 0755 "$vendor_dir"

download() {
    local url="$1" output="$2"
    curl --fail --location --retry 5 --retry-all-errors "$url" --output "$output"
    unzip -tq "$output" >/dev/null
}

wordpress="$vendor_dir/wordpress-${wordpress_version}-de_DE.zip"
wordpress_sha1_file="$vendor_dir/wordpress-${wordpress_version}-de_DE.zip.sha1"
woocommerce="$vendor_dir/woocommerce-${woocommerce_version}.zip"
redis_cache="$vendor_dir/redis-cache-${redis_cache_version}.zip"
storefront="$vendor_dir/storefront-${storefront_version}.zip"

download "https://de.wordpress.org/wordpress-${wordpress_version}-de_DE.zip" "$wordpress"
curl --fail --location --retry 5 --retry-all-errors \
    "https://de.wordpress.org/wordpress-${wordpress_version}-de_DE.zip.sha1" \
    --output "$wordpress_sha1_file"
download "https://downloads.wordpress.org/plugin/woocommerce.${woocommerce_version}.zip" "$woocommerce"
printf '%s  %s\n' "$woocommerce_sha256" "$woocommerce" | sha256sum --check --strict
download "https://downloads.wordpress.org/plugin/redis-cache.${redis_cache_version}.zip" "$redis_cache"
download "https://downloads.wordpress.org/theme/storefront.${storefront_version}.zip" "$storefront"

wordpress_sha1="$(tr -d '[:space:]' < "$wordpress_sha1_file")"
if [[ ! "$wordpress_sha1" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "The official WordPress SHA-1 response is invalid." >&2
    exit 1
fi
printf '%s  %s\n' "$wordpress_sha1" "$wordpress" | sha1sum --check --strict

unzip -p "$wordpress" wordpress/wp-includes/version.php \
    | grep -Fq "\$wp_version = '${wordpress_version}'"
unzip -p "$woocommerce" woocommerce/woocommerce.php \
    | grep -Eq "^[[:space:]]*\*[[:space:]]*Version:[[:space:]]*${woocommerce_version}([[:space:]]|$)"
unzip -p "$redis_cache" redis-cache/redis-cache.php \
    | grep -Eq "^[[:space:]]*\*[[:space:]]*Version:[[:space:]]*${redis_cache_version}([[:space:]]|$)"
unzip -p "$storefront" storefront/style.css \
    | grep -Eq "^Version:[[:space:]]*${storefront_version}([[:space:]]|$)"

(
    cd "$vendor_dir"
    sha256sum \
        "$(basename "$wordpress")" \
        "$(basename "$wordpress_sha1_file")" \
        "$(basename "$woocommerce")" \
        "$(basename "$redis_cache")" \
        "$(basename "$storefront")" > SHA256SUMS
)

chmod 0644 "$wordpress" "$wordpress_sha1_file" "$woocommerce" "$redis_cache" "$storefront" "$vendor_dir/SHA256SUMS"
echo "Bundled WordPress ${wordpress_version}, WooCommerce ${woocommerce_version}, Redis Object Cache ${redis_cache_version} and Storefront ${storefront_version}."
