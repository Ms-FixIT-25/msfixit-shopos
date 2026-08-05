#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init="$root/image/package/usr/local/sbin/msfixit-first-login-init"
wifi="$root/image/package/usr/local/sbin/msfixit-wifi-connect"
ssid="$root/image/package/etc/msfixit-shopos/wifi.env"
dropin="$root/image/package/etc/systemd/system/getty@tty1.service.d/shopos-first-login.conf"

bash -n "$init"
bash -n "$wifi"

grep -Fq 'user=shopadmin' "$init"
grep -Fq "chpasswd" "$init"
grep -Fq 'chage -d 0' "$init"
grep -Fq '/dev/console' "$init"
grep -Fq 'ConditionPathExists=!/var/lib/msfixit-shopos/first-login-initialized' "$dropin"
grep -Fq 'ExecStartPre=/bin/bash /usr/local/sbin/msfixit-first-login-init' "$dropin"
grep -Fxq 'SHOPOS_WIFI_SSID=Skynet' "$ssid"
grep -Fq 'nmcli --ask device wifi connect "$ssid"' "$wifi"

if grep -Eiq '(password|passwd|psk|secret)[[:space:]]*=' "$ssid"; then
    echo 'Wi-Fi secret must not be stored in the image configuration.' >&2
    exit 1
fi

if grep -Fq 'SHOPOS_WIFI_PASSWORD' "$wifi" "$ssid"; then
    echo 'Wi-Fi password variable must not exist in the repository.' >&2
    exit 1
fi

printf 'PASS: console-only one-time login and password-free Wi-Fi SSID bootstrap checks.\n'
