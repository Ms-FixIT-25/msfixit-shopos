.PHONY: package image-usb image-sd image-nvme check

package:
	bash scripts/build-package.sh

image-usb:
	bash scripts/build-image.sh usb

image-sd:
	bash scripts/build-image.sh sd

image-nvme:
	bash scripts/build-image.sh nvme

check:
	bash -n scripts/build-package.sh
	bash -n scripts/build-image.sh
	bash -n image/package/DEBIAN/postinst
	bash -n image/package/usr/local/sbin/msfixit-firstboot
	bash -n image/package/usr/local/sbin/msfixit-health
	bash -n image/package/usr/local/sbin/msfixit-backup
	bash -n image/package/usr/local/sbin/msfixit-status
