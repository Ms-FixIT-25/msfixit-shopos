#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init="$root/image/package/usr/local/sbin/msfixit-first-login-init"
wifi="$root/image/package/usr/local/sbin/msfixit-wifi-connect"
keepawake="$root/image/package/usr/local/sbin/msfixit-display-keepawake"
kiosk_session="$root/image/package/usr/local/sbin/msfixit-kiosk-session"
ssid="$root/image/package/etc/msfixit-shopos/wifi.env"
dropin="$root/image/package/etc/systemd/system/getty@tty1.service.d/shopos-first-login.conf"
first_login_service="$root/image/package/etc/systemd/system/msfixit-first-login.service"
keepawake_service="$root/image/package/etc/systemd/system/msfixit-display-keepawake.service"
kiosk_service="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
firstboot_service="$root/image/package/etc/systemd/system/msfixit-firstboot.service"
brand_service="$root/image/package/etc/systemd/system/msfixit-brand-shop.service"
control="$root/image/package/DEBIAN/control"
postinst="$root/image/package/DEBIAN/postinst"
layout="$root/scripts/postprocess-ab-image.sh"

bash -n "$init"
bash -n "$wifi"
bash -n "$keepawake"
bash -n "$kiosk_session"
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
grep -Fq 'SSID manuell auswählen oder eingeben' "$init"
grep -Fq 'Überspringen' "$init"
grep -Fq '/usr/local/sbin/msfixit-wifi-connect --manual' "$init"
grep -Fq 'ShopOS startet trotzdem vollständig lokal weiter.' "$init"
grep -Fq 'Die lokale ShopOS-Oberfläche wird jetzt gestartet.' "$init"

# Both automatic and manual choices must share the same delayed-hardware path.
grep -Fq 'case "${1:-}" in' "$wifi"
grep -Fq -- '--manual) mode=manual' "$wifi"
grep -Fq 'systemctl start NetworkManager.service' "$wifi"
grep -Fq 'rfkill unblock wlan' "$wifi"
grep -Fq 'modprobe brcmfmac' "$wifi"
grep -Fq 'udevadm settle' "$wifi"
grep -Fq 'for attempt in $(seq 1 45)' "$wifi"
grep -Fq 'nmcli -t -f DEVICE,TYPE device status' "$wifi"
grep -Fq 'nmcli device set "$wifi_device" managed yes' "$wifi"
grep -Fq 'nmcli device wifi rescan ifname "$wifi_device"' "$wifi"
grep -Fq 'nmcli --fields SSID,SIGNAL,SECURITY device wifi list ifname "$wifi_device"' "$wifi"
grep -Fq '[ "$mode" = auto ]' "$wifi"
grep -Fq 'WLAN-Passwort abgefragt' "$wifi"
grep -Fq 'nmcli --ask device wifi connect "$ssid" ifname "$wifi_device"' "$wifi"
grep -Fq 'wifi_diagnostics' "$wifi"
grep -Fxq 'SHOPOS_WIFI_SSID=Skynet' "$ssid"

for dependency in network-manager wpasupplicant rfkill iw wireless-regdb firmware-brcm80211; do
    grep -Eq "Depends:.*(^|, )${dependency}(,|$)" "$control" || {
        echo "Missing explicit Wi-Fi runtime dependency: $dependency" >&2
        exit 1
    }
done
grep -Fq 'systemctl enable NetworkManager.service' "$postinst"

# The interactive wizard must never block getty's ExecStartPre.
grep -Fq 'Wants=msfixit-first-login.service' "$dropin"
grep -Fq 'After=msfixit-first-login.service' "$dropin"
grep -Fq 'ExecStartPre=/bin/bash /usr/local/sbin/msfixit-display-keepawake /dev/tty1' "$dropin"
if grep -Fq 'msfixit-first-login-init' "$dropin"; then
    echo 'Interactive first-login setup must not run as a getty ExecStartPre.' >&2
    exit 1
fi

grep -Fq 'Before=getty@tty1.service msfixit-kiosk.service' "$first_login_service"
grep -Fq 'ConditionPathExists=!/var/lib/msfixit-shopos/first-setup-complete' "$first_login_service"
grep -Fq 'ExecStart=/usr/local/sbin/msfixit-first-login-init' "$first_login_service"
grep -Fq 'ExecStartPost=/bin/systemctl --no-block start msfixit-kiosk.service' "$first_login_service"
grep -Fq 'StandardInput=tty-force' "$first_login_service"
grep -Fq 'TTYPath=/dev/tty1' "$first_login_service"
grep -Fq 'TimeoutStartSec=infinity' "$first_login_service"

# The kiosk must fail closed if first-login or branding fails, while network
# connectivity remains optional for the local 127.0.0.1 appliance UI.
grep -Fq 'Requires=msfixit-brand-shop.service msfixit-first-login.service' "$kiosk_service"
grep -Fq 'After=local-fs.target nginx.service msfixit-brand-shop.service msfixit-first-login.service' "$kiosk_service"
grep -Fq 'Wants=nginx.service' "$kiosk_service"
if grep -Fq 'Wants=nginx.service msfixit-first-login.service' "$kiosk_service"; then
    echo 'Kiosk must require successful first-login rather than merely wanting it.' >&2
    exit 1
fi
grep -Fq 'ExecStartPre=/usr/bin/test -x /usr/bin/chromium' "$kiosk_service"
grep -Fq 'ExecStartPre=/usr/bin/test -x /usr/bin/xinit' "$kiosk_service"
grep -Fq 'TimeoutStartSec=4min' "$kiosk_service"
if grep -Fq 'network-online.target' "$kiosk_service" "$firstboot_service" "$brand_service"; then
    echo 'Local ShopOS provisioning and kiosk must not depend on network-online.target.' >&2
    exit 1
fi
grep -Fq 'After=local-fs.target' "$firstboot_service"
grep -Fq 'After=msfixit-firstboot.service msfixit-resource-budget.service' "$brand_service"

# Unsupported X/KMS DPMS features must never terminate the whole kiosk.
grep -Fq 'xset -dpms 2>/dev/null || true' "$kiosk_session"
grep -Fq 'xset s off 2>/dev/null || true' "$kiosk_session"
grep -Fq 'xset s noblank 2>/dev/null || true' "$kiosk_session"
grep -Fq 'curl --silent --fail --max-time 2 "$target_url"' "$kiosk_session"
grep -Fq 'local_ready=1' "$kiosk_session"
grep -Fq 'restarting kiosk session' "$kiosk_session"

grep -Fq 'setterm --blank 0 --powerdown 0' "$keepawake"
grep -Fq 'setterm --powersave off' "$keepawake"
grep -Fq 'setterm --blank poke' "$keepawake"
grep -Fq '\033[0;97;40m\033[2J\033[H\033[?25h' "$keepawake"
grep -Fq 'Before=msfixit-boot-console.service getty@tty1.service' "$keepawake_service"
grep -Fq 'ExecStart=/usr/local/sbin/msfixit-display-keepawake /dev/tty1' "$keepawake_service"

grep -Fq 'consoleblank=0' "$postinst"
grep -Fq 'systemctl enable msfixit-first-login.service' "$postinst"
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

printf 'PASS: automatic/manual Wi-Fi share resilient hardware discovery and kiosk requires successful first-login.\n'
