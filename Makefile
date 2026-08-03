.PHONY: package image-usb image-sd image-rpi4-usb image-rpi4-sd image-rpi5-usb image-rpi5-sd image-rpi5-nvme check

package:
	bash scripts/build-package.sh

# Default targets match the currently intended Raspberry Pi 4 Model B.
image-usb: image-rpi4-usb

image-sd: image-rpi4-sd

image-rpi4-usb:
	bash scripts/build-image.sh rpi4 usb

image-rpi4-sd:
	bash scripts/build-image.sh rpi4 sd

image-rpi5-usb:
	bash scripts/build-image.sh rpi5 usb

image-rpi5-sd:
	bash scripts/build-image.sh rpi5 sd

image-rpi5-nvme:
	bash scripts/build-image.sh rpi5 nvme

check:
	bash -n scripts/build-package.sh
	bash -n scripts/build-image.sh
	bash -n image/package/DEBIAN/postinst
	bash -n image/package/usr/local/sbin/msfixit-firstboot
	bash -n image/package/usr/local/sbin/msfixit-brand-shop
	bash -n image/package/usr/local/sbin/msfixit-catalog-init
	bash -n image/package/usr/local/sbin/msfixit-apply-config
	bash -n image/package/usr/local/sbin/msfixit-health
	bash -n image/package/usr/local/sbin/msfixit-backup
	bash -n image/package/usr/local/sbin/msfixit-status
	@test -s image/package/usr/share/msfixit-shopos/catalog/schema.sql
	@grep -q 'catalog_products' image/package/usr/share/msfixit-shopos/catalog/schema.sql
	@if command -v php >/dev/null 2>&1; then \
		php -l image/package/usr/local/sbin/msfixit-catalog; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-branding.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-catalog-bridge.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-commerce-provision.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-commerce-region.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-provision.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-render-branding.php; \
	fi
