#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
postinst="$root/image/package/DEBIAN/postinst"
control="$root/image/package/DEBIAN/control"
first_login_init="$root/image/package/usr/local/sbin/msfixit-first-login-init"
kiosk="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
x_session="$root/image/package/usr/local/sbin/msfixit-x-session"
setup_gui="$root/image/package/usr/local/sbin/msfixit-setup-gui"
office_print="$root/image/package/etc/systemd/system/msfixit-office-print.service"
office_worker="$root/image/package/etc/systemd/system/msfixit-office-worker.service"
time_helper="$root/image/package/usr/local/sbin/msfixit-time-bootstrap"
timesync="$root/image/package/etc/systemd/timesyncd.conf.d/msfixit-shopos.conf"
ssh_helper="$root/image/package/usr/local/sbin/msfixit-ssh-recovery-init"
ssh_service="$root/image/package/etc/systemd/system/msfixit-ssh-recovery.service"
ssh_auth="$root/image/package/etc/ssh/sshd_config.d/60-msfixit-admin-auth.conf"
sudo_policy="$root/image/package/etc/sudoers.d/99-msfixit-admin-password"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for path in "$postinst" "$control" "$first_login_init" "$kiosk" "$x_session" "$setup_gui" "$office_print" "$office_worker" "$time_helper" "$timesync" "$ssh_helper" "$ssh_service" "$ssh_auth" "$sudo_policy"; do
    [ -s "$path" ] || fail "missing required file: $path"
done

bash -n "$time_helper"
bash -n "$ssh_helper"
bash -n "$first_login_init"
bash -n "$x_session"
python3 -m py_compile "$setup_gui"

grep -Eq 'chmod 0755 .*msfixit-wifi-connect' "$postinst" || fail 'installed Wi-Fi helper is not forced executable'
grep -Eq 'chmod 0755 .*msfixit-x-session' "$postinst" || fail 'persistent X session helper is not forced executable'
grep -Eq 'chmod 0755 .*msfixit-setup-gui' "$postinst" || fail 'graphical setup shell is not forced executable'
grep -Fq 'systemctl disable systemd-networkd.service' "$postinst" || fail 'systemd-networkd must be disabled'
grep -Fq 'systemctl enable NetworkManager.service' "$postinst" || fail 'NetworkManager must own networking'
grep -Fq 'systemctl disable msfixit-first-login.service' "$postinst" || fail 'legacy tty first-login must not auto-start'
grep -Fq 'systemctl disable msfixit-boot-console.service' "$postinst" || fail 'legacy tty boot console must not auto-start'
grep -Fq 'systemctl enable msfixit-kiosk.service' "$postinst" || fail 'persistent X display service must auto-start'

grep -Fq 'BUILD_EPOCH' "$time_helper" || fail 'offline clock fallback is missing'
grep -Fq 'time.cloudflare.com' "$timesync" || fail 'Cloudflare NTP is missing'
grep -Fq 'time.google.com' "$timesync" || fail 'Google NTP is missing'
grep -Fq 'pool.ntp.org' "$timesync" || fail 'pool NTP fallback is missing'

# Real hardware must transition Plymouth -> one Xorg instance. First-login and
# Chromium are clients of that same server; neither may seize a VT itself.
grep -Fq 'python3-gi' "$control" || fail 'GTK Python runtime for graphical first-login is missing'
grep -Fq 'gir1.2-gtk-3.0' "$control" || fail 'GTK bindings for graphical first-login are missing'
grep -Fq 'gir1.2-vte-2.91' "$control" || fail 'VTE bindings for graphical first-login are missing'
if grep -Eq 'Depends:.*(^|, )xterm(,|$)' "$control"; then
    fail 'legacy xterm must not be a production first-login dependency'
fi
if grep -Fq '/usr/bin/xterm' "$x_session"; then
    fail 'legacy xterm must not be executed in the visible first-login path'
fi
grep -Fq 'ExecStart=/usr/bin/xinit /usr/local/sbin/msfixit-x-session -- :0 vt7 -keeptty -nolisten tcp' "$kiosk" || fail 'display service does not own one persistent local-only Xorg server'
if grep -Eq 'TTYPath=|StandardInput=tty|StandardInput=tty-force' "$kiosk"; then
    fail 'persistent X display service must not use systemd tty ownership directives'
fi
if grep -Fq '/dev/tty1' "$first_login_init"; then
    fail 'first-login must not seize tty1 when running inside X'
fi
grep -Fq '/usr/local/sbin/msfixit-setup-gui' "$x_session" || fail 'first-login is not launched through the GTK setup shell'
grep -Fq '/usr/local/sbin/msfixit-first-login-init' "$setup_gui" || fail 'GTK shell does not launch the proven first-login logic'
grep -Fq 'Vte.Terminal' "$setup_gui" || fail 'GTK shell does not provide controlled embedded input'
grep -Fq 'self.fullscreen()' "$setup_gui" || fail 'setup shell must own the full display instead of exposing raw X background'
grep -Fq 'runuser -u "$kiosk_user"' "$x_session" || fail 'X session does not drop privileges for kiosk client'
grep -Fq '/usr/local/sbin/msfixit-kiosk-session' "$x_session" || fail 'same X session does not hand off to kiosk client'
grep -Fq 'xhost +SI:localuser:' "$x_session" || fail 'X access is not limited to the dedicated local kiosk user'

if grep -Fq 'network-online.target' "$office_print" "$office_worker"; then
    fail 'local Office workers must not depend on network-online'
fi

# SSH recovery and human-admin password policy.
grep -Fq 'SHOPOS-SSH-TRUSTED-MAC' "$ssh_helper" || fail 'trusted MAC boot-file import is missing'
grep -Fq 'SHOPOS-ADMIN.pub' "$ssh_helper" || fail 'public-key boot-file import is missing'
grep -Fq 'ether saddr $trusted_mac tcp dport 22 accept' "$ssh_helper" || fail 'SSH MAC allow rule is missing'
grep -Fq 'tcp dport 22 drop' "$ssh_helper" || fail 'SSH fallback drop rule is missing'
grep -Fq 'authorized_keys' "$ssh_helper" || fail 'SSH authorized_keys provisioning is missing'
grep -Fq '/usr/local/sbin/msfixit-ssh-recovery-init' "$first_login_init" || fail 'first-login must provision recovery SSH before Wi-Fi'
grep -Fq 'passwd -u "$username"' "$first_login_init" || fail 'administrator must be unlocked after password provisioning'
grep -Fxq 'PasswordAuthentication yes' "$ssh_auth" || fail 'SSH password authentication is not enabled'
grep -Fxq 'PubkeyAuthentication yes' "$ssh_auth" || fail 'SSH public-key authentication is not enabled'
grep -Fxq 'UsePAM yes' "$ssh_auth" || fail 'SSH must use PAM account state'
grep -Fxq 'PermitRootLogin no' "$ssh_auth" || fail 'root SSH login must remain disabled'
grep -Fxq 'Defaults:%sudo authenticate' "$sudo_policy" || fail 'human sudo administrators must authenticate'
grep -Fxq '%sudo ALL=(ALL:ALL) PASSWD: ALL' "$sudo_policy" || fail 'sudo must use the first-login administrator password'

if grep -Eiq '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}' "$ssh_helper" "$ssh_service" "$ssh_auth" "$sudo_policy"; then
    fail 'a concrete administrator workstation MAC was embedded in product policy'
fi

printf 'PASS: ShopOS uses one persistent Xorg server from Plymouth handoff through a modern GTK first-login shell and kiosk, remains offline-capable, and preserves hardened admin recovery.\n'
