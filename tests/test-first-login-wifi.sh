#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init="$root/image/package/usr/local/sbin/msfixit-first-login-init"
wifi="$root/image/package/usr/local/sbin/msfixit-wifi-connect"
keepawake="$root/image/package/usr/local/sbin/msfixit-display-keepawake"
ssid="$root/image/package/etc/msfixit-shopos/wifi.env"
dropin="$root/image/package/etc/systemd/system/getty@tty1.service.d/shopos-first-login.conf"
first_login_service="$root/image/package/etc/systemd/system/msfixit-first-login.service"
keepawake_service="$root/image/package/etc/systemd/system/msfixit-display-keepawake.service"
kiosk_service="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
postinst="$root/image/package/DEBIAN/postinst"
layout="$root/scripts/postprocess-ab-image.sh"

bash -n "$init"
bash -n "$wifi"
bash -n "$keepawake"
bash -n "$layout"

test -s "$first_login_service"

grep -Fq 'exec </dev/tty1 >/dev/tty1 2>&1' "$init"
grep -Fq 'Benutzername [${default_user}]' "$init"
grep -Fq 'Passwort wiederholen' "$init"
grep -Fq 'mindestens 8 Zeichen' "$init"
if grep -Fq 'mindestens 12 Zeichen' "$init"; then
    echo 'The local appliance setup must not require twelve password characters.' >&2
    exit 1
fi
grep -Fq 'useradd --create-home' "$init"
grep -Fq 'usermod --lock "$default_user"' "$init"
grep -Fq 'WLAN einrichten?' "$init"
grep -Fq 'WLAN automatisch suchen und verbinden' "$init"
grep -Fq 'SSID manuell eingeben' "$init"
grep -Fq 'Überspringen' "$init"
grep -Fq 'nmcli device wifi rescan' "$wifi"
grep -Fq 'nmcli --fields SSID,SIGNAL,SECURITY device wifi list' "$wifi"
grep -Fq 'WLAN-Passwort abgefragt' "$wifi"
grep -Fq 'nmcli --ask device wifi connect "$ssid"' "$wifi"
grep -Fxq 'SHOPOS_WIFI_SSID=Skynet' "$ssid"

# The interactive wizard must never block getty's ExecStartPre. systemd gives
# start-pre commands a finite startup timeout, which previously killed and
# restarted the prompt about every 90 seconds on the real Raspberry Pi.
grep -Fq 'Wants=msfixit-first-login.service' "$dropin"
grep -Fq 'After=msfixit-first-login.service' "$dropin"
grep -Fq 'ExecStartPre=/bin/bash /usr/local/sbin/msfixit-display-keepawake /dev/tty1' "$dropin"
if grep -Fq 'msfixit-first-login-init' "$dropin"; then
    echo 'Interactive first-login setup must not run as a getty ExecStartPre.' >&2
    exit 1
fi

grep -Fq 'Before=getty@tty1.service msfixit-kiosk.service' "$first_login_service"
grep -Fq 'After=local-fs.target systemd-vconsole-setup.service msfixit-display-keepawake.service msfixit-boot-console.service' "$first_login_service"
grep -Fq 'ConditionPathExists=!/var/lib/msfixit-shopos/first-setup-complete' "$first_login_service"
grep -Fq 'ExecStartPre=/usr/local/sbin/msfixit-display-keepawake /dev/tty1' "$first_login_service"
grep -Fq 'ExecStart=/usr/local/sbin/msfixit-first-login-init' "$first_login_service"
grep -Fq 'StandardInput=tty-force' "$first_login_service"
grep -Fq 'TTYPath=/dev/tty1' "$first_login_service"
grep -Fq 'TimeoutStartSec=infinity' "$first_login_service"
grep -Fq 'After=network-online.target nginx.service msfixit-brand-shop.service msfixit-first-login.service' "$kiosk_service"
grep -Fq 'Wants=network-online.target msfixit-first-login.service' "$kiosk_service"

grep -Fq 'setterm --blank 0 --powerdown 0' "$keepawake"
grep -Fq 'setterm --powersave off' "$keepawake"
grep -Fq 'setterm --blank poke' "$keepawake"
grep -Fq '\033[0;97;40m\033[2J\033[H\033[?25h' "$keepawake"
grep -Fq 'Before=msfixit-boot-console.service getty@tty1.service' "$keepawake_service"
grep -Fq 'ExecStart=/usr/local/sbin/msfixit-display-keepawake /dev/tty1' "$keepawake_service"

grep -Fq 'consoleblank=0' "$postinst"
grep -Fq 'consoleblank=[^[:space:]]+' "$postinst"
grep -Fq 'systemctl enable msfixit-display-keepawake.service' "$postinst"
grep -Fq 'systemctl enable msfixit-first-login.service' "$postinst"
# Package-install time is not enough: the A/B postprocessor touches the actual
# boot partition and must enforce the final kernel policy as well.
grep -Fq "tokens = [token for token in tokens if not token.startswith('consoleblank=')]" "$layout"
grep -Fq "tokens.append('consoleblank=0')" "$layout"

if grep -Fq 'ConditionPathExists=' "$dropin"; then
    echo 'The tty1 getty must remain available after setup.' >&2
    exit 1
fi

if grep -Eiq '(password|passwd|psk|secret)[[:space:]]*=' "$ssid"; then
    echo 'Wi-Fi secret must not be stored in the image configuration.' >&2
    exit 1
fi

if grep -Fq 'SHOPOS_WIFI_PASSWORD' "$init" "$wifi" "$ssid"; then
    echo 'Wi-Fi password variables must not exist in the repository.' >&2
    exit 1
fi

if grep -Eq 'One-time password|chage -d 0|/dev/urandom' "$init"; then
    echo 'The obsolete generated bootstrap-password flow is still present.' >&2
    exit 1
fi

printf 'PASS: first-login owns tty1 without getty timeouts and keeps the display awake until kiosk handoff.\n'
