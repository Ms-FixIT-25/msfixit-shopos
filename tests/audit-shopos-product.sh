#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0
warnings=0

err() { printf '::error::%s\n' "$*"; errors=$((errors+1)); }
warn() { printf '::warning::%s\n' "$*"; warnings=$((warnings+1)); }
info() { printf 'INFO: %s\n' "$*"; }

pkg="$root/image/package"

info 'Audit: shell and graphical setup syntax'
while IFS= read -r -d '' f; do
  case "$f" in
    *.sh|*/usr/local/sbin/*|*/DEBIAN/postinst)
      if head -n1 "$f" 2>/dev/null | grep -Eq '^#!.*(bash|sh)'; then
        bash -n "$f" 2>/dev/null || err "shell syntax failed: ${f#$root/}"
      fi
      ;;
  esac
done < <(find "$pkg" "$root/tests" -type f -print0)
python3 -m py_compile "$pkg/usr/local/sbin/msfixit-setup-gui" 2>/dev/null || err 'GTK setup shell Python syntax failed'

info 'Audit: executable helpers installed by package'
for helper in msfixit-first-login-init msfixit-wifi-connect msfixit-time-bootstrap msfixit-ssh-recovery-init msfixit-kiosk-session msfixit-x-session msfixit-setup-gui; do
  [ -s "$pkg/usr/local/sbin/$helper" ] || { err "missing helper: $helper"; continue; }
  grep -Eq "chmod 0755 .*${helper}" "$pkg/DEBIAN/postinst" || err "postinst does not force executable mode for $helper"
done

info 'Audit: networking ownership and offline boot'
grep -Fq 'systemctl enable NetworkManager.service' "$pkg/DEBIAN/postinst" || err 'NetworkManager is not enabled'
grep -Fq 'systemctl disable systemd-networkd.service' "$pkg/DEBIAN/postinst" || err 'systemd-networkd is not disabled'
grep -Fq 'systemctl disable systemd-networkd-wait-online.service' "$pkg/DEBIAN/postinst" || err 'systemd-networkd wait-online is not disabled'
while IFS= read -r unit; do
  case "$unit" in
    *msfixit-time-bootstrap.service|*msfixit-update-agent*|*msfixit-cloudflared*) continue ;;
  esac
  if grep -Fq 'network-online.target' "$unit"; then
    warn "local service still references network-online.target: ${unit#$root/}"
  fi
done < <(find "$pkg/etc/systemd/system" -type f -name '*.service' | sort)

info 'Audit: Plymouth -> persistent X -> GTK setup -> kiosk handoff'
kiosk="$pkg/etc/systemd/system/msfixit-kiosk.service"
x_session="$pkg/usr/local/sbin/msfixit-x-session"
setup_gui="$pkg/usr/local/sbin/msfixit-setup-gui"
first_init="$pkg/usr/local/sbin/msfixit-first-login-init"
for f in "$kiosk" "$x_session" "$setup_gui" "$first_init"; do [ -s "$f" ] || err "missing display component: ${f#$root/}"; done

grep -Fq 'systemctl disable msfixit-first-login.service' "$pkg/DEBIAN/postinst" || err 'legacy tty first-login still auto-starts'
grep -Fq 'systemctl disable msfixit-boot-console.service' "$pkg/DEBIAN/postinst" || err 'legacy tty boot console still auto-starts'
grep -Fq 'systemctl enable msfixit-kiosk.service' "$pkg/DEBIAN/postinst" || err 'persistent X display service is not enabled'
grep -Fq 'ExecStartPre=-/usr/bin/plymouth quit --retain-splash' "$kiosk" || err 'X display does not explicitly take over from Plymouth'
grep -Fq 'ExecStart=/usr/bin/xinit /usr/local/sbin/msfixit-x-session -- :0 vt7 -keeptty -nolisten tcp' "$kiosk" || err 'kiosk does not own one local-only persistent Xorg server'
grep -Fq 'ConditionPathExists=/usr/local/sbin/msfixit-setup-gui' "$kiosk" || err 'kiosk does not require the graphical setup shell'
if grep -Eq 'TTYPath=|StandardInput=tty|StandardInput=tty-force' "$kiosk"; then err 'persistent X service still claims a systemd TTY'; fi
if grep -Fq '/usr/bin/xterm' "$kiosk" || grep -Fq 'xterm' "$x_session"; then err 'raw xterm remains in the production first-login path'; fi
if grep -Fq '/dev/tty1' "$first_init"; then err 'first-login still seizes tty1'; fi
grep -Fq 'readonly setup_marker=/var/lib/msfixit-shopos/first-setup-complete' "$x_session" || err 'persistent X session does not own the setup completion gate'
grep -Fq '/usr/local/sbin/msfixit-setup-gui' "$x_session" || err 'persistent X session does not launch GTK setup'
grep -Fq 'runuser -u "$kiosk_user"' "$x_session" || err 'persistent X session does not drop privileges for kiosk client'
grep -Fq '/usr/local/sbin/msfixit-kiosk-session' "$x_session" || err 'persistent X session does not hand off to kiosk client'
grep -Fq 'class SetupWindow(Gtk.Window)' "$setup_gui" || err 'graphical setup is not a GTK window'
grep -Fq 'self.fullscreen()' "$setup_gui" || err 'graphical setup is not full-screen'
grep -Fq 'Vte.Terminal()' "$setup_gui" || err 'graphical setup does not contain the controlled provisioning surface'

info 'Audit: administrator authentication policy'
sshd="$pkg/etc/ssh/sshd_config.d/60-msfixit-admin-auth.conf"
sudoers="$pkg/etc/sudoers.d/99-msfixit-admin-password"
[ -s "$sshd" ] || err 'missing ShopOS sshd policy'
[ -s "$sudoers" ] || err 'missing human-admin sudoers policy'
[ ! -s "$sshd" ] || grep -Eq '^PasswordAuthentication[[:space:]]+yes$' "$sshd" || err 'SSH password authentication is not explicitly enabled'
[ ! -s "$sshd" ] || grep -Eq '^PubkeyAuthentication[[:space:]]+yes$' "$sshd" || err 'SSH public-key authentication is not explicitly enabled'
[ ! -s "$sshd" ] || grep -Eq '^UsePAM[[:space:]]+yes$' "$sshd" || err 'SSH PAM authentication is not explicitly enabled'
[ ! -s "$sshd" ] || grep -Eq '^PermitRootLogin[[:space:]]+no$' "$sshd" || err 'root SSH login is not explicitly disabled'
[ ! -s "$sudoers" ] || grep -Fq 'Defaults:%sudo authenticate' "$sudoers" || err 'sudo administrators are not explicitly required to authenticate'
[ ! -s "$sudoers" ] || grep -Fq '%sudo ALL=(ALL:ALL) PASSWD: ALL' "$sudoers" || err 'human sudo administrators are not explicitly password-gated'
grep -Fq 'passwd -u "$username"' "$first_init" || err 'first-login does not explicitly unlock the provisioned administrator'

info 'Audit: MAC-gated SSH recovery'
ssh_recovery="$pkg/usr/local/sbin/msfixit-ssh-recovery-init"
[ -s "$ssh_recovery" ] || err 'missing SSH recovery helper'
if [ -s "$ssh_recovery" ]; then
  grep -Fq 'SHOPOS-SSH-TRUSTED-MAC' "$ssh_recovery" || err 'SSH recovery does not read trusted MAC from boot media'
  grep -Fq 'SHOPOS-ADMIN.pub' "$ssh_recovery" || err 'SSH recovery does not read public key from boot media'
  grep -Fq 'ether saddr $trusted_mac tcp dport 22 accept' "$ssh_recovery" || err 'SSH recovery lacks MAC allow rule'
  grep -Fq 'tcp dport 22 drop' "$ssh_recovery" || err 'SSH recovery lacks default SSH drop rule'
fi

info 'Audit: obvious secret / credential leakage'
if grep -RInE --exclude='audit-shopos-product.sh' '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|password[[:space:]]*=[[:space:]]*[^$<{[:space:]][^[:space:]]+|passwd[[:space:]]+[A-Za-z0-9._-]+)' "$pkg" 2>/dev/null | head -n 20 | grep -q .; then
  warn 'possible embedded credential/private-key material found; inspect audit log matches'
fi

info 'Audit: permissive file modes and privileged services'
while IFS= read -r f; do
  mode="$(stat -c '%a' "$f" 2>/dev/null || true)"
  case "$mode" in
    666|667|676|677|766|767|776|777) warn "world/group-writable packaged file: ${f#$root/} mode=$mode" ;;
  esac
done < <(find "$pkg" -type f)
while IFS= read -r unit; do
  grep -Eq '^User=root$' "$unit" && ! grep -Eq '^NoNewPrivileges=true$' "$unit" && warn "root service without NoNewPrivileges=true: ${unit#$root/}"
done < <(find "$pkg/etc/systemd/system" -type f -name '*.service' | sort)

printf '\nAUDIT SUMMARY: errors=%d warnings=%d\n' "$errors" "$warnings"
if (( errors > 0 )); then
  exit 1
fi
exit 0
