#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

assert_contains() {
    local expected="$1" file="$2"
    if ! grep -Fq "$expected" "$file"; then
        echo "Missing expected text in ${file}: ${expected}" >&2
        exit 1
    fi
}

bash -n scripts/fetch-vendor-assets.sh
bash -n image/package/usr/local/bin/wp
bash -n image/package/usr/local/bin/shopos-version
bash -n image/package/usr/local/sbin/msfixit-boot-state
bash -n image/package/usr/local/sbin/msfixit-boot-console
bash -n image/package/usr/local/sbin/msfixit-firstboot-progress

for file in \
    image/package/usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.plymouth \
    image/package/usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.script \
    image/package/etc/systemd/system/msfixit-boot-console.service \
    image/package/etc/update-motd.d/10-msfixit-shopos; do
    test -s "$file"
done

assert_contains 'ModuleName=script' image/package/usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.plymouth
assert_contains 'MS. FIXIT' image/package/usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.script
assert_contains 'SHOPOS' image/package/usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.script

assert_contains 'plymouth-set-default-theme -R msfixit-shopos' image/package/DEBIAN/postinst
assert_contains 'quiet splash loglevel=3' image/package/DEBIAN/postinst
assert_contains 'systemctl enable msfixit-boot-console.service' image/package/DEBIAN/postinst
assert_contains 'plymouth, plymouth-themes, initramfs-tools' image/package/DEBIAN/control

assert_contains 'Before=getty@tty1.service' image/package/etc/systemd/system/msfixit-boot-console.service
assert_contains 'TTYPath=/dev/tty1' image/package/etc/systemd/system/msfixit-boot-console.service
assert_contains 'ConditionPathExists=!/data/.shopos-ready' image/package/etc/systemd/system/msfixit-boot-console.service
assert_contains 'ExecStart=/usr/local/sbin/msfixit-firstboot-progress' image/package/etc/systemd/system/msfixit-firstboot.service
assert_contains '/data/.shopos-ready' image/package/etc/systemd/system/msfixit-brand-shop.service
assert_contains 'msfixit-boot-state ready 100' image/package/etc/systemd/system/msfixit-brand-shop.service

assert_contains 'readonly wordpress_version=7.0.2' scripts/fetch-vendor-assets.sh
assert_contains 'readonly woocommerce_version=10.9.4' scripts/fetch-vendor-assets.sh
assert_contains 'readonly redis_cache_version=2.8.0' scripts/fetch-vendor-assets.sh
assert_contains 'readonly storefront_version=4.6.2' scripts/fetch-vendor-assets.sh
assert_contains 'https://de.wordpress.org/wordpress-${wordpress_version}-de_DE.zip' scripts/fetch-vendor-assets.sh
assert_contains 'https://de.wordpress.org/wordpress-${wordpress_version}-de_DE.zip.sha1' scripts/fetch-vendor-assets.sh
assert_contains 'https://downloads.wordpress.org/plugin/woocommerce.${woocommerce_version}.zip' scripts/fetch-vendor-assets.sh
assert_contains 'https://downloads.wordpress.org/plugin/redis-cache.${redis_cache_version}.zip' scripts/fetch-vendor-assets.sh
assert_contains 'https://downloads.wordpress.org/theme/storefront.${storefront_version}.zip' scripts/fetch-vendor-assets.sh
assert_contains 'sha1sum --check --strict' scripts/fetch-vendor-assets.sh
assert_contains '/usr/local/lib/msfixit-shopos/wp-cli.phar' image/package/usr/local/bin/wp
assert_contains 'WordPress ${bundled_wordpress} (de_DE) installed from the ShopOS image.' image/package/usr/local/bin/wp
assert_contains 'WORDPRESS_VERSION=7.0.2' image/package/usr/share/msfixit-shopos/shopos.env.example

if grep -Fq 'WORDPRESS_VERSION=latest' image/package/usr/share/msfixit-shopos/shopos.env.example; then
    echo 'The default image must not depend on the latest network release.' >&2
    exit 1
fi

echo 'ShopOS boot experience and offline payload checks passed.'
