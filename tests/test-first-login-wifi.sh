#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init="$root/image/package/usr/local/sbin/msfixit-first-login-init"
wifi="$root/image/package/usr/local/sbin/msfixit-wifi-connect"
ssid="$root/image/package/etc/msfixit-shopos/wifi.env"
dropin="$root/image/package/etc/systemd/system/getty@tty1.service.d/shopos-first-login.conf"

bash -n "$init"
bash -n "$wifi"

grep -Fq 'exec </dev/tty1 >/dev/tty1 2>&1' "$init"
grep -Fq 'Benutzername [${default_user}]' "$init"
grep -Fq 'Passwort wiederholen' "$init"
grep -Fq 'mindestens 12 Zeichen' "$init"
grep -Fq 'useradd --create-home' "$init"
grep -Fq 'usermod --lock "$default_user"' "$init"
grep -Fq 'WLAN einrichten?' "$init"
grep -Fq 'Automatisch mit der vorkonfigurierten SSID verbinden' "$init"
grep -Fq 'Anderes WLAN manuell auswählen' "$init"
grep -Fq 'Überspringen' "$init"
grep -Fq 'nmcli --ask device wifi connect "$manual_ssid"' "$init"
grep -Fq 'ExecStartPre=/bin/bash /usr/local/sbin/msfixit-first-login-init' "$dropin"
grep -Fxq 'SHOPOS_WIFI_SSID=Skynet' "$ssid"
grep -Fq 'nmcli --ask device wifi connect "$ssid"' "$wifi"

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

printf 'PASS: interactive user creation and optional password-free Wi-Fi bootstrap checks.\n'
