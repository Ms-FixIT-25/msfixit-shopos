#!/usr/bin/env bash

# Shared helpers for deterministic, offline ShopOS application provisioning.
# The package build downloads and verifies these archives once. Runtime setup
# must consume the exact embedded files instead of silently reaching out to the
# public WordPress infrastructure.

readonly MSFIXIT_VENDOR_DIR="${MSFIXIT_VENDOR_DIR:-/usr/share/msfixit-shopos/vendor}"
readonly MSFIXIT_BUILD_INFO="${MSFIXIT_BUILD_INFO:-/usr/share/msfixit-shopos/build-info.txt}"

msfixit_build_value() {
    local key="$1"
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$MSFIXIT_BUILD_INFO"
}

msfixit_vendor_require_file() {
    local file="$1"
    if [ ! -s "$file" ]; then
        printf 'Required bundled vendor asset is missing: %s\n' "$file" >&2
        return 1
    fi
    printf '%s\n' "$file"
}

msfixit_vendor_verify() {
    test -s "$MSFIXIT_BUILD_INFO"
    test -s "$MSFIXIT_VENDOR_DIR/SHA256SUMS"
    (
        cd "$MSFIXIT_VENDOR_DIR"
        sha256sum --check --strict SHA256SUMS
    )
}

msfixit_vendor_wordpress_version() {
    msfixit_build_value WORDPRESS_VERSION
}

msfixit_vendor_wordpress_locale() {
    local locale
    locale="$(msfixit_build_value WORDPRESS_LOCALE)"
    printf '%s\n' "${locale:-de_DE}"
}

msfixit_vendor_wordpress_archive() {
    local version locale
    version="$(msfixit_vendor_wordpress_version)"
    locale="$(msfixit_vendor_wordpress_locale)"
    msfixit_vendor_require_file "$MSFIXIT_VENDOR_DIR/wordpress-${version}-${locale}.zip"
}

msfixit_vendor_woocommerce_archive() {
    local version
    version="$(msfixit_build_value WOOCOMMERCE_VERSION)"
    msfixit_vendor_require_file "$MSFIXIT_VENDOR_DIR/woocommerce-${version}.zip"
}

msfixit_vendor_redis_cache_archive() {
    local version
    version="$(msfixit_build_value REDIS_CACHE_VERSION)"
    msfixit_vendor_require_file "$MSFIXIT_VENDOR_DIR/redis-cache-${version}.zip"
}

msfixit_vendor_storefront_archive() {
    local version
    version="$(msfixit_build_value STOREFRONT_VERSION)"
    msfixit_vendor_require_file "$MSFIXIT_VENDOR_DIR/storefront-${version}.zip"
}
