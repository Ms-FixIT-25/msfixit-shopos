#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
control="$root/image/package/DEBIAN/control"
sensors="$root/image/package/usr/lib/msfixit-shopos/hardware_manager/sensors.py"
models="$root/image/package/usr/lib/msfixit-shopos/hardware_manager/models.py"
kiosk_service="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
hardware_test="$root/tests/test-shopos-hardware-manager.sh"
first_login_test="$root/tests/test-first-login-wifi.sh"

# Physical keyboard/mouse and HID-style barcode scanners rely on the standard
# Linux input stack rather than vendor-specific drivers.
grep -Eq 'Depends:.*(^|, )xserver-xorg-input-libinput(,|$)' "$control"
grep -Fq 'SupplementaryGroups=video render input' "$kiosk_service"
grep -Fq 'physical keyboard and mouse would not work in kiosk mode' "$first_login_test"

# Generic USB discovery must remain vendor-neutral so keyboards, mice and
# USB HID scanners are visible even when no device-specific package exists.
grep -Fq 'def usb' "$sensors"
grep -Fq '/sys/bus/usb/devices' "$sensors"
grep -Fq 'idVendor' "$sensors"
grep -Fq 'idProduct' "$sensors"
grep -Fq 'class UsbDevice' "$models"
if grep -Eiq '(zebra|honeywell|datalogic|symbol).*(required|allowlist)|allowlist.*(vendor|product)' "$sensors"; then
    echo 'USB input discovery must not require a scanner-vendor allowlist.' >&2
    exit 1
fi

# Printing is discovered through the system print service rather than by a
# hard-coded USB model list, covering USB and network-backed CUPS queues.
grep -Eq 'Depends:.*(^|, )cups-client(,|$)' "$control"
grep -Fq 'def printers' "$sensors"
grep -Fq '/usr/bin/lpstat' "$sensors"
grep -Fq 'PrinterDevice' "$models"
grep -Fq 'def printers' "$hardware_test"

# The current contract intentionally distinguishes what CI can prove from what
# needs physical acceptance testing. HID key events, mouse movement, a real
# barcode scan and an actual print page cannot be fabricated by static CI.
printf '%s\n' \
  'PASS: ShopOS includes vendor-neutral USB discovery, libinput keyboard/mouse/HID support and CUPS printer discovery.' \
  'PHYSICAL-GATE: verify key input, pointer input, HID barcode scan + Enter, USB hotplug and a real printer test page on Raspberry Pi hardware.'
