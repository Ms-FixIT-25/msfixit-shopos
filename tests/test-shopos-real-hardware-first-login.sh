#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
postinst="$root/image/package/DEBIAN/postinst"
first_login_init="$root/image/package/usr/local/sbin/msfixit-first-login-init"
first_login="$root/image/package/etc/systemd/system/msfixit-first-login.service"
kiosk="$root/image/package/etc/systemd/system/msfixit-kiosk.service"
boot_console="$root/image/package/etc/systemd/system/msfixit-boot-console.service"
office_print="$root/image/package/etc/systemd/system/msfixit-office-print.service"
office_worker="$root/image/package/etc/systemd/system/msfixit-office-worker.service"
time_service="$root/image/package/etc/systemd/system/msfixit-time-bootstrap.service"
time_helper="$root/image/package/usr/local/sbin/msfixit-time-bootstrap"
timesync="$root/image/package/etc/systemd/timesyncd.conf.d/msfixit-shopos.conf"
ssh_helper="$root/image/package/usr/local/sbin/msfixit-ssh-recovery-init"
ssh_service="$root/image/package/etc/systemd/system/msfixit-ssh-recovery.service"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for path in "$postinst" "$first_login_init" "$first_login" "$kiosk" "$boot_console" "$office_print" "$office_worker" "$time_service" "$time_helper" "$timesync" "$ssh_helper" "$ssh_service"; do
    [ -s "$path" ] || fail "missing required file: $path"
done

bash -n "$time_helper"
bash -n "$ssh_helper"
bash -n "$first_login_init"

grep -Eq 'chmod 0755 .*msfixit-wifi-connect' "$postinst" \
    || fail 'installed Wi-Fi helper is not forced executable'
grep -Eq 'chmod 0755 .*msfixit-time-bootstrap' "$postinst" \
    || fail 'time bootstrap helper is not forced executable'
grep -Eq 'chmod 0755 .*msfixit-ssh-recovery-init' "$postinst" \
    || fail 'SSH recovery helper is not forced executable'
grep -Fq 'systemctl enable systemd-timesyncd.service' "$postinst" \
    || fail 'systemd-timesyncd is not enabled'
grep -Fq 'systemctl enable msfixit-time-bootstrap.service' "$postinst" \
    || fail 'time bootstrap service is not enabled'
grep -Fq 'systemctl enable ssh.service' "$postinst" \
    || fail 'SSH service must remain available for local recovery'
grep -Fq 'systemctl enable msfixit-ssh-recovery.service' "$postinst" \
    || fail 'MAC-gated SSH recovery service is not enabled'
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

# Recovery SSH is provisioned from the boot partition so no customer/device
# identity or public key is baked into the repository image.
grep -Fq 'SHOPOS-SSH-TRUSTED-MAC' "$ssh_helper" \
    || fail 'SSH recovery does not read the trusted MAC from the boot partition'
grep -Fq 'SHOPOS-ADMIN.pub' "$ssh_helper" \
    || fail 'SSH recovery does not import a boot-partition public key'
grep -Fq 'ether saddr $trusted_mac tcp dport 22 accept' "$ssh_helper" \
    || fail 'SSH firewall does not allow the configured LAN source MAC'
grep -Fq 'tcp dport 22 drop' "$ssh_helper" \
    || fail 'SSH firewall does not reject other source MACs'
grep -Fq 'authorized_keys' "$ssh_helper" \
    || fail 'SSH recovery does not install authorized_keys'
grep -Fq 'chmod 0600 "$home_dir/.ssh/authorized_keys"' "$ssh_helper" \
    || fail 'SSH authorized_keys permissions are not hardened'
grep -Fq 'Before=ssh.service nftables.service' "$ssh_service" \
    || fail 'SSH recovery gate must be prepared before sshd and nftables'
grep -Fq '/usr/local/sbin/msfixit-ssh-recovery-init' "$first_login_init" \
    || fail 'first login must provision SSH recovery before Wi-Fi setup can fail'
grep -Fq 'passwd -u "$username"' "$first_login_init" \
    || fail 'new administrator must be explicitly unlocked after password provisioning'

# Never regress into embedding the observed test workstation MAC in public code.
if grep -RFiq 'd8:43:ae:c8:cd:26' "$root/image" "$root/tests"; then
    fail 'a concrete administrator workstation MAC was embedded in the repository'
fi

printf 'PASS: real-hardware first-login keeps Wi-Fi executable, seeds time offline, uses NetworkManager only, preserves the Plymouth/VT/kiosk handoff, and provides MAC-gated key-based SSH recovery.\n'
