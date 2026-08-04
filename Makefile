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
	bash -n tests/test-office-privileges.sh
	bash -n tests/test-compliance.sh
	bash -n tests/test-compliance-strict.sh
	bash -n tests/test-compliance-numbering.sh
	bash -n tests/test-tax-renderer-boundary.sh
	bash -n tests/test-also.sh
	bash -n tests/test-also-content.sh
	bash -n tests/test-partners.sh
	bash -n image/package/DEBIAN/postinst
	bash -n image/package/usr/local/sbin/msfixit-firstboot
	bash -n image/package/usr/local/sbin/msfixit-brand-shop
	bash -n image/package/usr/local/sbin/msfixit-catalog-init
	bash -n image/package/usr/local/sbin/msfixit-office-init
	bash -n image/package/usr/local/sbin/msfixit-also-init
	bash -n image/package/usr/local/sbin/msfixit-also-content-sync
	bash -n image/package/usr/local/sbin/msfixit-partners-init
	bash -n image/package/usr/local/sbin/msfixit-discovery
	bash -n image/package/usr/local/sbin/msfixit-office-worker
	bash -n image/package/usr/local/sbin/msfixit-office-dunning
	bash -n image/package/usr/local/sbin/msfixit-office-print
	bash -n image/package/usr/local/sbin/msfixit-compliance-worker
	bash -n image/package/usr/local/sbin/msfixit-apply-config
	bash -n image/package/usr/local/sbin/msfixit-health
	bash -n image/package/usr/local/sbin/msfixit-backup
	bash -n image/package/usr/local/sbin/msfixit-status
	@test -s image/package/usr/share/msfixit-shopos/catalog/schema.sql
	@test -s image/package/usr/share/msfixit-shopos/catalog/guards.sql
	@test -s image/package/usr/share/msfixit-shopos/office/schema.sql
	@test -s image/package/usr/share/msfixit-shopos/office/operational.sql
	@test -s image/package/usr/share/msfixit-shopos/office/migrations.sql
	@test -s image/package/usr/share/msfixit-shopos/compliance/schema.sql
	@test -s image/package/usr/share/msfixit-shopos/compliance/guards.sql
	@test -s image/package/usr/share/msfixit-shopos/compliance/strict-guards.sql
	@test -s image/package/usr/share/msfixit-shopos/compliance/strict-migrations.sql
	@test -s image/package/usr/share/msfixit-shopos/compliance/tax-decision-migrations.sql
	@test -s image/package/usr/share/msfixit-shopos/compliance/renderer-guards.sql
	@test -s image/package/usr/share/msfixit-shopos/also/schema.sql
	@test -s image/package/usr/share/msfixit-shopos/also/content.sql
	@test -s image/package/usr/share/msfixit-shopos/also/content-guards.sql
	@test -s image/package/usr/share/msfixit-shopos/also/also.env.example
	@test -s image/package/usr/share/msfixit-shopos/discovery/discovery.env.example
	@test -s image/package/usr/share/msfixit-shopos/discovery/discovery-lib.php
	@test -s image/package/usr/share/msfixit-shopos/partners/schema.sql
	@test -s image/package/usr/share/msfixit-shopos/wordpress/assets/msfixit-discovery.js
	@test -s image/package/usr/share/msfixit-shopos/wordpress/assets/msfixit-discovery.css
	@test -s image/package/usr/share/msfixit-shopos/wordpress/assets/msfixit-help-center.css
	@grep -q 'catalog_products' image/package/usr/share/msfixit-shopos/catalog/schema.sql
	@grep -q 'no_reassign' image/package/usr/share/msfixit-shopos/catalog/guards.sql
	@grep -q 'office_documents' image/package/usr/share/msfixit-shopos/office/schema.sql
	@grep -q 'office_document_holds' image/package/usr/share/msfixit-shopos/office/operational.sql
	@grep -q 'allocations_immutable' image/package/usr/share/msfixit-shopos/office/operational.sql
	@grep -q 'office_v2_applied' image/package/usr/share/msfixit-shopos/office/migrations.sql
	@grep -q 'compliance_market_profiles' image/package/usr/share/msfixit-shopos/compliance/schema.sql
	@grep -q 'compliance_before_final' image/package/usr/share/msfixit-shopos/compliance/guards.sql
	@grep -q 'Verified registration requires actor' image/package/usr/share/msfixit-shopos/compliance/strict-guards.sql
	@grep -q 'before number allocation' image/package/usr/share/msfixit-shopos/compliance/strict-migrations.sql
	@grep -q 'superseding decision' image/package/usr/share/msfixit-shopos/compliance/tax-decision-migrations.sql
	@grep -q 'advanced DACH tax invoice renderer' image/package/usr/share/msfixit-shopos/compliance/renderer-guards.sql
	@grep -q 'supplier_import_runs' image/package/usr/share/msfixit-shopos/also/schema.sql
	@grep -q 'supplier_content_profiles' image/package/usr/share/msfixit-shopos/also/content.sql
	@grep -q 'remote_only' image/package/usr/share/msfixit-shopos/also/content.sql
	@grep -q 'supplier_content_changed' image/package/usr/share/msfixit-shopos/also/content-guards.sql
	@grep -q 'AT_PILOT_AUTO_PUBLISH=no' image/package/usr/share/msfixit-shopos/also/also.env.example
	@grep -q 'ALSO_CONTENT_MEDIA_MODE=remote_only' image/package/usr/share/msfixit-shopos/also/also.env.example
	@grep -q 'GOOGLE_MERCHANT_FEED_ENABLED=no' image/package/usr/share/msfixit-shopos/discovery/discovery.env.example
	@grep -q 'msfixit_discovery_publication_audit' image/package/usr/share/msfixit-shopos/discovery/discovery-lib.php
	@grep -q 'partner_profiles' image/package/usr/share/msfixit-shopos/partners/schema.sql
	@grep -q 'Partner logo requires separately verified usage rights' image/package/usr/share/msfixit-shopos/partners/schema.sql
	@grep -q 'msfixit_help_center' image/package/usr/share/msfixit-shopos/wordpress/msfixit-help-center.php
	@if command -v php >/dev/null 2>&1; then \
		php -l tests/test-discovery.php; \
		php tests/test-discovery.php; \
		php -l image/package/usr/local/sbin/msfixit-catalog; \
		php -l image/package/usr/local/sbin/msfixit-office; \
		php -l image/package/usr/local/sbin/msfixit-compliance; \
		php -l image/package/usr/local/sbin/msfixit-tax-decision; \
		php -l image/package/usr/local/sbin/msfixit-also; \
		php -l image/package/usr/local/sbin/msfixit-also-content; \
		php -l image/package/usr/local/sbin/msfixit-partners; \
		php -l image/package/usr/share/msfixit-shopos/discovery/discovery-lib.php; \
		php -l image/package/usr/share/msfixit-shopos/office/office-lib.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-branding.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-catalog-bridge.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-commerce-provision.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-commerce-region.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-office-bridge.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-compliance.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-compliance-runtime.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-at-pilot.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-also-draft.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-also-content.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-also-content-apply.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-discovery.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-discovery-provision.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-discovery-cli.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-help-center.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-help-provision.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-provision.php; \
		php -l image/package/usr/share/msfixit-shopos/wordpress/msfixit-render-branding.php; \
	fi
