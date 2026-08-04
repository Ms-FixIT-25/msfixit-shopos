#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 PACKAGE_STAGE" >&2
    exit 2
fi

readonly stage="$1"
readonly vendor_dir="$stage/usr/share/msfixit-shopos/vendor"
readonly wordpress_version=7.0.2
readonly wordpress_sha1=f84f755adcf6732c6f681f0430358f0e09593c20
readonly woocommerce_version=10.9.4
readonly redis_cache_version=2.8.0
readonly storefront_version=4.6.2

install -d -m 0755 "$vendor_dir"

download() {
    local url="$1" output="$2"
    curl --fail --location --retry 5 --retry-all-errors "$url" --output "$output"
    unzip -tq "$output" >/dev/null
}

wordpress="$vendor_dir/wordpress-${wordpress_version}-de_DE.zip"
woocommerce="$vendor_dir/woocommerce-${woocommerce_version}.zip"
redis_cache="$vendor_dir/redis-cache-${redis_cache_version}.zip"
storefront="$vendor_dir/storefront-${storefront_version}.zip"

download "https://de.wordpress.org/wordpress-${wordpress_version}-de_DE.zip" "$wordpress"
download "https://downloads.wordpress.org/plugin/woocommerce.${woocommerce_version}.zip" "$woocommerce"
download "https://downloads.wordpress.org/plugin/redis-cache.${redis_cache_version}.zip" "$redis_cache"
download "https://downloads.wordpress.org/theme/storefront.${storefront_version}.zip" "$storefront"

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
        "$(basename "$woocommerce")" \
        "$(basename "$redis_cache")" \
        "$(basename "$storefront")" > SHA256SUMS
)

chmod 0644 "$wordpress" "$woocommerce" "$redis_cache" "$storefront" "$vendor_dir/SHA256SUMS"
echo "Bundled WordPress ${wordpress_version}, WooCommerce ${woocommerce_version}, Redis Object Cache ${redis_cache_version} and Storefront ${storefront_version}."
