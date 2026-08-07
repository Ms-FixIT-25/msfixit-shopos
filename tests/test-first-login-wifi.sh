#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init="$root/image/package/usr/local/sbin/msfixit-first-login-init"
wifi="$root/image/package/usr/local/sbin/msfixit-wifi-connect"
keepawake="$root/image/package/usr/local/sbin/msfixit-display-keepawake"
ssid="$root/image/package/etc/msfixit-shopos/wifi.env"
dropin="$root/image/package/etc/systemd/system/getty@tty1.service.d/shopos-first-login.conf"
keepawake_service="$root/image/package/etc/systemd/system/msfixit-display-keepawake.service"
postinst="$root/image/package/DEBIAN/postinst"

bash -n "$init"
bash -n "$wifi"
bash -n "$keepawake"

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
grep -Fq 'ExecStartPre=/bin/bash /usr/local/sbin/msfixit-display-keepawake /dev/tty1' "$dropin"
grep -Fq 'ExecStartPre=/bin/bash /usr/local/sbin/msfixit-first-login-init' "$dropin"
grep -Fxq 'SHOPOS_WIFI_SSID=Skynet' "$ssid"

keepawake_line="$(grep -Fn 'msfixit-display-keepawake' "$dropin" | head -n 1 | cut -d: -f1)"
setup_line="$(grep -Fn 'msfixit-first-login-init' "$dropin" | head -n 1 | cut -d: -f1)"
if [ -z "$keepawake_line" ] || [ -z "$setup_line" ] || [ "$keepawake_line" -ge "$setup_line" ]; then
    echo 'Display blanking must be disabled before the password prompt starts.' >&2
    exit 1
fi

grep -Fq 'setterm --blank 0 --powerdown 0' "$keepawake"
grep -Fq 'setterm --powersave off' "$keepawake"
grep -Fq '\033[0;97;40m\033[?25h' "$keepawake"
grep -Fq 'Before=msfixit-boot-console.service getty@tty1.service' "$keepawake_service"
grep -Fq 'ExecStart=/usr/local/sbin/msfixit-display-keepawake /dev/tty1' "$keepawake_service"
grep -Fq 'consoleblank=0' "$postinst"
grep -Fq 'consoleblank=[^[:space:]]+' "$postinst"
grep -Fq 'systemctl enable msfixit-display-keepawake.service' "$postinst"

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

printf 'PASS: interactive setup keeps tty1 bright and awake while discovering Wi-Fi.\n'
