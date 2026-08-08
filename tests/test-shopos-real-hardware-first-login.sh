#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
postinst="$root/image/package/DEBIAN/postinst"
first_login="$root/image/package/etc/systemd/system/msfixit-first-login.service"
kiosk="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
boot_console="$root/image/package/etc/systemd/system/msfixit-boot-console.service"
office_print="$root/image/package/etc/systemd/system/msfixit-office-print.service"
office_worker="$root/image/package/etc/systemd/system/msfixit-office-worker.service"
time_service="$root/image/package/etc/systemd/system/msfixit-time-bootstrap.service"
time_helper="$root/image/package/usr/local/sbin/msfixit-time-bootstrap"
timesync="$root/image/package/etc/systemd/timesyncd.conf.d/msfixit-shopos.conf"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for path in "$postinst" "$first_login" "$kiosk" "$boot_console" "$office_print" "$office_worker" "$time_service" "$time_helper" "$timesync"; do
    [ -s "$path" ] || fail "missing required file: $path"
done

bash -n "$time_helper"

grep -Eq 'chmod 0755 .*msfixit-wifi-connect' "$postinst" \
    || fail 'installed Wi-Fi helper is not forced executable'
grep -Eq 'chmod 0755 .*msfixit-time-bootstrap' "$postinst" \
    || fail 'time bootstrap helper is not forced executable'
grep -Fq 'systemctl enable systemd-timesyncd.service' "$postinst" \
    || fail 'systemd-timesyncd is not enabled'
grep -Fq 'systemctl enable msfixit-time-bootstrap.service' "$postinst" \
    || fail 'time bootstrap service is not enabled'
grep -Fq 'systemctl disable systemd-networkd.service' "$postinst" \
    || fail 'systemd-networkd must be disabled when NetworkManager owns networking'
grep -Fq 'systemctl disable systemd-networkd-wait-online.service' "$postinst" \
    || fail 'systemd-networkd wait-online must not degrade or delay ShopOS boot'
grep -Fq 'systemctl enable NetworkManager.service' "$postinst" \
    || fail 'NetworkManager must remain the canonical ShopOS network manager'

grep -Fq 'BUILD_EPOCH' "$time_helper" \
    || fail 'offline clock fallback is not derived from packaged build time'
grep -Fq 'time.cloudflare.com' "$timesync" \
    || fail 'public NTP primary is missing'
grep -Fq 'time.google.com' "$timesync" \
    || fail 'public NTP secondary is missing'
grep -Fq 'pool.ntp.org' "$timesync" \
    || fail 'public pool NTP fallback is missing'

if grep -Fq 'Requires=msfixit-brand-shop.service msfixit-first-login.service' "$kiosk"; then
    fail 'kiosk must not require the interactive first-login unit'
fi
grep -Fq 'ConditionPathExists=/var/lib/msfixit-shopos/first-setup-complete' "$kiosk" \
    || fail 'kiosk must wait for the completed first-setup marker'
grep -Fq 'ExecStartPost=/bin/systemctl --no-block start msfixit-kiosk.service' "$first_login" \
    || fail 'completed first login must trigger kiosk start'
grep -Fq 'TTYReset=no' "$first_login" \
    || fail 'first-login handoff must not reset the real-hardware VT'
grep -Fq 'TTYVHangup=no' "$first_login" \
    || fail 'first-login handoff must not hang up the keyboard VT'

if grep -Fq 'network-online.target' "$boot_console"; then
    fail 'boot console must never wait for network-online on an offline appliance'
fi
grep -Fq 'Before=getty@tty1.service msfixit-first-login.service' "$boot_console" \
    || fail 'boot console must hand tty1 to first login in a defined order'
grep -Fq 'TTYReset=no' "$boot_console" \
    || fail 'boot console must not reset VT state during Plymouth/first-login handoff'
grep -Fq 'TTYVHangup=no' "$boot_console" \
    || fail 'boot console must not hang up physical keyboard input'
grep -Fq 'TTYVTDisallocate=no' "$boot_console" \
    || fail 'boot console must preserve framebuffer/VT state for the next owner'

if grep -Fq 'network-online.target' "$office_print" "$office_worker"; then
    fail 'local Office workers must not block or fail solely because the appliance is offline'
fi

printf 'PASS: real-hardware first-login keeps Wi-Fi executable, seeds time offline, uses NetworkManager only, and preserves the Plymouth/VT/kiosk handoff.\n'
