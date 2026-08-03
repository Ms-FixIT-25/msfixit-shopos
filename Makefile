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
	bash -n tests/test-catalog.sh
	bash -n tests/test-office.sh
	bash -n tests/test-office-migrations.sh
	bash -n tests/test-office-guards.sh
	bash -n image/package/DEBIAN/postinst
	bash -n image/package/usr/local/sbin/msfixit-firstboot
	bash -n image/package/usr/local/sbin/msfixit-brand-shop
	bash -n image/package/usr/local/sbin/msfixit-catalog-init
	bash -n image/package/usr/local/sbin/msfixit-office-init
	bash -n image/package/usr/local/sbin/msfixit-office-worker
	bash -n image/package/usr/local/sbin/msfixit-office-dunning
	bash -n image/package/usr/local/sbin/msfixit-office-print
	bash -n image/package/usr/local/sbin/msfixit-apply-config
	bash -n image/package/usr/local/sbin/msfixit-health
	bash -n image/package/usr/local/sbin/msfixit-backup
	bash -n image/package/usr/local/sbin/msfixit-status
	@test -s image/package/usr/share/msfixit-shopos/catalog/schema.sql
	@test -s image/package/usr/share/msfixit-shopos/catalog/guards.sql
	@test -s image/package/usr/share/msfixit-shopos/office/schema.sql
	@test -s image/package/usr/share/msfixit-shopos/office/operational.sql
	@test -s image/package/usr/share/msfixit-shopos/office/migrations.sql
	@grep -q 'catalog_products' image/package/usr/share/msfixit-shopos/catalog/schema.sql
	@grep -q 'no_reassign' image/package/usr/share/msfixit-shopos/catalog/guards.sql
	@grep -q 'office_documents' image/package/usr/share/msfixit-shopos/office/schema.sql
	@grep -q 'office_document_holds' image/package/usr/share/msfixit-shopos/office/operational.sql
	@grep -q 'allocations_immutable' image/package/usr/share/msfixit-shopos/office/operational.sql
	@grep -q 'office_v2_applied' image/package/usr/share/msfixit-shopos/office/migrations.sql
	@if command -v php >/dev/null 2>&1; then \
		php -l image/package/usr/local/sbin/msfixit-catalog; \
		php -l image/package/usr/local/sbin/msfixit-office; \
		php -l image/package/usr/share/msfixit-shopos/office/office-lib.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-branding.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-catalog-bridge.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-commerce-provision.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-commerce-region.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-office-bridge.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-provision.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-render-branding.php; \
	fi
