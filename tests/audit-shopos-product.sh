#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0
warnings=0

err() { printf '::error::%s\n' "$*"; errors=$((errors+1)); }
warn() { printf '::warning::%s\n' "$*"; warnings=$((warnings+1)); }
info() { printf 'INFO: %s\n' "$*"; }

pkg="$root/image/package"

info 'Audit: shell syntax'
while IFS= read -r -d '' f; do
  case "$f" in
    *.sh|*/usr/local/sbin/*|*/DEBIAN/postinst)
      if head -n1 "$f" 2>/dev/null | grep -Eq '^#!.*(bash|sh)'; then
        bash -n "$f" 2>/dev/null || err "shell syntax failed: ${f#$root/}"
      fi
      ;;
  esac
done < <(find "$pkg" "$root/tests" -type f -print0)

info 'Audit: executable helpers installed by package'
for helper in msfixit-first-login-init msfixit-wifi-connect msfixit-time-bootstrap msfixit-ssh-recovery-init msfixit-kiosk-session; do
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

info 'Audit: first-login, Plymouth, VT and kiosk handoff'
boot="$pkg/etc/systemd/system/msfixit-boot-console.service"
first="$pkg/etc/systemd/system/msfixit-first-login.service"
kiosk="$pkg/etc/systemd/system/msfixit-kiosk.service"
for f in "$boot" "$first" "$kiosk"; do [ -s "$f" ] || err "missing systemd unit: ${f#$root/}"; done
for setting in TTYReset=no TTYVHangup=no; do
  grep -Fq "$setting" "$first" || err "first-login missing $setting"
done
grep -Fq 'TTYVTDisallocate=no' "$boot" || err 'boot console may disallocate the physical VT'
if grep -Fq 'network-online.target' "$boot"; then err 'boot console blocks on network-online.target'; fi
grep -Fq 'ConditionPathExists=/var/lib/msfixit-shopos/first-setup-complete' "$kiosk" || err 'kiosk is not gated by completed first setup'
if grep -Fq 'Requires=msfixit-brand-shop.service msfixit-first-login.service' "$kiosk"; then err 'kiosk still hard-requires interactive first-login'; fi

info 'Audit: administrator authentication policy'
sshd="$pkg/etc/ssh/sshd_config.d/90-msfixit-shopos-admin.conf"
sudoers="$pkg/etc/sudoers.d/msfixit-shopos-admin"
[ -s "$sshd" ] || err 'missing ShopOS sshd policy'
[ -s "$sudoers" ] || err 'missing human-admin sudoers policy'
[ ! -s "$sshd" ] || grep -Eq '^PasswordAuthentication[[:space:]]+yes$' "$sshd" || err 'SSH password authentication is not explicitly enabled'
[ ! -s "$sshd" ] || grep -Eq '^PubkeyAuthentication[[:space:]]+yes$' "$sshd" || err 'SSH public-key authentication is not explicitly enabled'
[ ! -s "$sshd" ] || grep -Eq '^UsePAM[[:space:]]+yes$' "$sshd" || err 'SSH PAM authentication is not explicitly enabled'
[ ! -s "$sshd" ] || grep -Eq '^PermitRootLogin[[:space:]]+no$' "$sshd" || err 'root SSH login is not explicitly disabled'
[ ! -s "$sudoers" ] || grep -Fq '%sudo ALL=(ALL:ALL) PASSWD: ALL' "$sudoers" || err 'human sudo administrators are not explicitly password-gated'

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

info 'Audit: permissive file modes and dangerous service directives'
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
