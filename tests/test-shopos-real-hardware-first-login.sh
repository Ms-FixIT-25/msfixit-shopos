#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
postinst="$root/image/package/DEBIAN/postinst"
first_login="$root/image/package/etc/systemd/system/msfixit-first-login.service"
kiosk="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
time_service="$root/image/package/etc/systemd/system/msfixit-time-bootstrap.service"
time_helper="$root/image/package/usr/local/sbin/msfixit-time-bootstrap"
timesync="$root/image/package/etc/systemd/timesyncd.conf.d/msfixit-shopos.conf"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for path in "$postinst" "$first_login" "$kiosk" "$time_service" "$time_helper" "$timesync"; do
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

printf 'PASS: real-hardware first-login keeps Wi-Fi executable, seeds time offline, syncs NTP online, and hands off cleanly to kiosk.\n'
