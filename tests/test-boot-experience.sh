#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

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

grep -Fq 'ModuleName=script' image/package/usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.plymouth
grep -Fq 'MS. FIXIT' image/package/usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.script
grep -Fq 'SHOPOS' image/package/usr/share/plymouth/themes/msfixit-shopos/msfixit-shopos.script

grep -Fq 'plymouth-set-default-theme -R msfixit-shopos' image/package/DEBIAN/postinst
grep -Fq 'quiet splash loglevel=3' image/package/DEBIAN/postinst
grep -Fq 'systemctl enable msfixit-boot-console.service' image/package/DEBIAN/postinst
grep -Fq 'plymouth, plymouth-themes, initramfs-tools' image/package/DEBIAN/control

grep -Fq 'Before=getty@tty1.service' image/package/etc/systemd/system/msfixit-boot-console.service
grep -Fq 'TTYPath=/dev/tty1' image/package/etc/systemd/system/msfixit-boot-console.service
grep -Fq 'ConditionPathExists=!/data/.shopos-ready' image/package/etc/systemd/system/msfixit-boot-console.service
grep -Fq 'ExecStart=/usr/local/sbin/msfixit-firstboot-progress' image/package/etc/systemd/system/msfixit-firstboot.service
grep -Fq '/data/.shopos-ready' image/package/etc/systemd/system/msfixit-brand-shop.service
grep -Fq 'msfixit-boot-state ready 100' image/package/etc/systemd/system/msfixit-brand-shop.service

grep -Fq 'wordpress-7.0.2-de_DE.zip' scripts/fetch-vendor-assets.sh
grep -Fq 'woocommerce.10.9.4.zip' scripts/fetch-vendor-assets.sh
grep -Fq 'redis-cache.2.8.0.zip' scripts/fetch-vendor-assets.sh
grep -Fq 'storefront.4.6.2.zip' scripts/fetch-vendor-assets.sh
grep -Fq 'f84f755adcf6732c6f681f0430358f0e09593c20' scripts/fetch-vendor-assets.sh
grep -Fq '/usr/local/lib/msfixit-shopos/wp-cli.phar' image/package/usr/local/bin/wp
grep -Fq 'WordPress 7.0.2 (de_DE) installed from the ShopOS image.' image/package/usr/local/bin/wp
grep -Fq 'WORDPRESS_VERSION=7.0.2' image/package/usr/share/msfixit-shopos/shopos.env.example

if grep -Fq 'WORDPRESS_VERSION=latest' image/package/usr/share/msfixit-shopos/shopos.env.example; then
    echo 'The default image must not depend on the latest network release.' >&2
    exit 1
fi

echo 'ShopOS boot experience and offline payload checks passed.'
