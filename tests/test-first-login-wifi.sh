#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init="$root/image/package/usr/local/sbin/msfixit-first-login-init"
wifi="$root/image/package/usr/local/sbin/msfixit-wifi-connect"
x_session="$root/image/package/usr/local/sbin/msfixit-x-session"
setup_gui="$root/image/package/usr/local/sbin/msfixit-setup-gui"
kiosk_session="$root/image/package/usr/local/sbin/msfixit-kiosk-session"
ssid="$root/image/package/etc/msfixit-shopos/wifi.env"
nm_config="$root/image/package/etc/NetworkManager/conf.d/20-shopos-wifi.conf"
kiosk_service="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
firstboot_service="$root/image/package/etc/systemd/system/msfixit-firstboot.service"
brand_service="$root/image/package/etc/systemd/system/msfixit-brand-shop.service"
admin_init_service="$root/image/package/etc/systemd/system/msfixit-admin-console-init.service"
control="$root/image/package/DEBIAN/control"
postinst="$root/image/package/DEBIAN/postinst"
layout="$root/scripts/postprocess-ab-image.sh"

for file in "$init" "$wifi" "$x_session" "$setup_gui" "$kiosk_session" "$ssid" "$nm_config" "$kiosk_service" "$admin_init_service" "$control" "$postinst"; do
    test -s "$file"
done

bash -n "$init"
bash -n "$wifi"
bash -n "$x_session"
bash -n "$kiosk_session"
bash -n "$layout"
python3 -m py_compile "$setup_gui"

# Human administrator provisioning remains the same contract even though the
# interaction is now presented by the graphical X/GTK shell.
grep -Fq 'Benutzername [${default_user}]' "$init"
grep -Fq 'Passwort wiederholen' "$init"
grep -Fq 'mindestens 8 Zeichen' "$init"
if grep -Fq 'mindestens 12 Zeichen' "$init"; then
    echo 'The local appliance setup must not require twelve password characters.' >&2
    exit 1
fi
grep -Fq 'useradd --create-home' "$init"
grep -Fq 'usermod --lock "$default_user"' "$init"
grep -Fq 'passwd -u "$username"' "$init"
grep -Fq '/usr/local/sbin/msfixit-ssh-recovery-init' "$init"
grep -Fq 'WLAN einrichten?' "$init"
grep -Fq 'WLAN automatisch suchen und verbinden' "$init"
grep -Fq 'SSID manuell auswählen oder eingeben' "$init"
grep -Fq 'Überspringen' "$init"
grep -Fq '/usr/local/sbin/msfixit-wifi-connect --manual' "$init"
grep -Fq 'ShopOS startet trotzdem vollständig lokal weiter.' "$init"
grep -Fq 'im selben X-Server gestartet' "$init"
if grep -Fq '/dev/tty1' "$init"; then
    echo 'Graphical first-login must never seize tty1.' >&2
    exit 1
fi

# Both automatic and manual Wi-Fi choices must share the same delayed-hardware path.
grep -Fq 'case "${1:-}" in' "$wifi"
grep -Fq -- '--manual) mode=manual' "$wifi"
grep -Fq 'systemctl start NetworkManager.service' "$wifi"
grep -Fq 'rfkill unblock wlan' "$wifi"
grep -Fq 'modprobe brcmfmac' "$wifi"
grep -Fq 'udevadm settle' "$wifi"
grep -Fq 'nmcli networking on' "$wifi"
grep -Fq 'nmcli radio wifi on' "$wifi"
grep -Fq 'iw reg set "$wifi_country"' "$wifi"
grep -Fq 'for attempt in $(seq 1 45)' "$wifi"
grep -Fq 'nmcli -t -f DEVICE,TYPE device status' "$wifi"
grep -Fq 'nmcli device set "$wifi_device" managed yes' "$wifi"
grep -Fq 'nmcli device wifi rescan ifname "$wifi_device"' "$wifi"
grep -Fq 'nmcli --fields SSID,SIGNAL,SECURITY device wifi list ifname "$wifi_device"' "$wifi"
grep -Fq '[ "$mode" = auto ]' "$wifi"
grep -Fq 'WLAN-Passwort abgefragt' "$wifi"
grep -Fq 'nmcli --ask --wait 90 device wifi connect "$ssid" ifname "$wifi_device"' "$wifi"
grep -Fq '100*) connected=1' "$wifi"
grep -Fq 'connection.autoconnect yes' "$wifi"
grep -Fq 'wifi_diagnostics' "$wifi"
grep -Fxq 'SHOPOS_WIFI_SSID=Skynet' "$ssid"
grep -Fxq 'SHOPOS_WIFI_COUNTRY=AT' "$ssid"
grep -Fq '[ifupdown]' "$nm_config"
grep -Fq 'managed=true' "$nm_config"

for dependency in network-manager wpasupplicant rfkill iw wireless-regdb firmware-brcm80211; do
    grep -Eq "Depends:.*(^|, )${dependency}(,|$)" "$control" || {
        echo "Missing explicit Wi-Fi runtime dependency: $dependency" >&2
        exit 1
    }
done
for dependency in xserver-xorg-input-libinput python3-gi gir1.2-gtk-3.0 gir1.2-vte-2.91; do
    grep -Eq "Depends:.*(^|, )${dependency}(,|$)" "$control" || {
        echo "Missing graphical first-login dependency: $dependency" >&2
        exit 1
    }
done
if grep -Eq 'Depends:.*(^|, )xterm(,|$)' "$control"; then
    echo 'Raw xterm must not be a production first-login dependency.' >&2
    exit 1
fi

grep -Fq 'systemctl enable NetworkManager.service' "$postinst"
grep -Fq 'systemctl enable msfixit-admin-console-init.service' "$postinst"
grep -Fq 'systemctl disable msfixit-first-login.service' "$postinst"
grep -Fq 'systemctl disable msfixit-boot-console.service' "$postinst"
grep -Fq 'systemctl enable msfixit-kiosk.service' "$postinst"
grep -Eq 'chmod 0755 .*msfixit-wifi-connect' "$postinst"
grep -Eq 'chmod 0755 .*msfixit-x-session' "$postinst"
grep -Eq 'chmod 0755 .*msfixit-setup-gui' "$postinst"

# One Xorg instance owns the display from Plymouth handoff through setup and
# kiosk. The completion marker is deliberately enforced inside that session,
# not as a ConditionPathExists on the service, because the service must start
# before first-login exists in order to display the GUI.
grep -Fq 'Requires=msfixit-brand-shop.service msfixit-admin-console-init.service' "$kiosk_service"
grep -Fq 'After=local-fs.target systemd-logind.service msfixit-brand-shop.service msfixit-admin-console-init.service' "$kiosk_service"
grep -Fq 'Wants=nginx.service NetworkManager.service' "$kiosk_service"
grep -Fq 'ConditionPathExists=/usr/local/sbin/msfixit-setup-gui' "$kiosk_service"
grep -Fq 'ExecStartPre=/usr/bin/test -x /usr/local/sbin/msfixit-setup-gui' "$kiosk_service"
grep -Fq 'ExecStartPre=-/usr/bin/plymouth quit --retain-splash' "$kiosk_service"
grep -Fq 'ExecStart=/usr/bin/xinit /usr/local/sbin/msfixit-x-session -- :0 vt7 -keeptty -nolisten tcp' "$kiosk_service"
grep -Fq 'TimeoutStartSec=4min' "$kiosk_service"
if grep -Eq 'TTYPath=|StandardInput=tty|StandardInput=tty-force' "$kiosk_service"; then
    echo 'Persistent X display service must not claim a systemd TTY.' >&2
    exit 1
fi
if grep -Fq '/usr/bin/xterm' "$kiosk_service"; then
    echo 'Persistent X display service must not require xterm.' >&2
    exit 1
fi

grep -Fq 'readonly setup_marker=/var/lib/msfixit-shopos/first-setup-complete' "$x_session"
grep -Fq '/usr/local/sbin/msfixit-setup-gui' "$x_session"
grep -Fq '[ -e "$setup_marker" ]' "$x_session"
grep -Fq 'runuser -u "$kiosk_user"' "$x_session"
grep -Fq '/usr/local/sbin/msfixit-kiosk-session' "$x_session"
grep -Fq 'xhost +SI:localuser:' "$x_session"
if grep -Fq 'xterm' "$x_session"; then
    echo 'Persistent X session must use the GTK setup shell, not xterm.' >&2
    exit 1
fi

# The visible setup shell must be full-screen, branded and embed the tested
# provisioning process instead of exposing a raw virtual terminal.
grep -Fq 'class SetupWindow(Gtk.Window)' "$setup_gui"
grep -Fq 'self.fullscreen()' "$setup_gui"
grep -Fq 'MS. FIXIT' "$setup_gui"
grep -Fq 'SHOPOS  •  ERSTEINRICHTUNG' "$setup_gui"
grep -Fq 'Vte.Terminal()' "$setup_gui"
grep -Fq 'SETUP_COMMAND = ["/usr/local/sbin/msfixit-first-login-init"]' "$setup_gui"
grep -Fq 'first-setup-complete' "$setup_gui"

grep -Fq 'Requires=msfixit-firstboot.service' "$admin_init_service"
grep -Fq 'After=local-fs.target msfixit-firstboot.service' "$admin_init_service"
if grep -Fq 'network-online.target' "$kiosk_service" "$firstboot_service" "$brand_service"; then
    echo 'Local ShopOS provisioning and kiosk must not depend on network-online.target.' >&2
    exit 1
fi
grep -Fq 'After=local-fs.target' "$firstboot_service"
grep -Fq 'After=msfixit-firstboot.service msfixit-resource-budget.service' "$brand_service"

# Unsupported X/KMS DPMS features must never terminate the whole kiosk.
grep -Fq 'xset -dpms 2>/dev/null || true' "$x_session"
grep -Fq 'xset s off 2>/dev/null || true' "$x_session"
grep -Fq 'xset s noblank 2>/dev/null || true' "$x_session"
grep -Fq 'curl --silent --fail --max-time 2 "$target_url"' "$kiosk_session"
grep -Fq 'local_ready=1' "$kiosk_session"
grep -Fq 'restarting kiosk session' "$kiosk_session"

grep -Fq 'consoleblank=0' "$postinst"
grep -Fq "tokens = [token for token in tokens if not token.startswith('consoleblank=')]" "$layout"
grep -Fq "tokens.append('consoleblank=0')" "$layout"

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

printf 'PASS: graphical first-login, physical X input, persistent Wi-Fi and same-X kiosk handoff are required.\n'
