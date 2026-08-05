#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
page="$root/image/package/usr/share/msfixit-shopos/admin-console/public/store.php"
sudoers="$root/image/package/etc/sudoers.d/msfixit-shopos-app-install"
php -l "$page"
grep -Fq "session_name('SHOPOSADMIN')" "$page"
grep -Fq 'hash_equals(csrfToken(),$token)' "$page"
grep -Fq "confirm_install" "$page"
grep -Fq "bypass_shell" "$page"
grep -Fq "'/usr/local/sbin/msfixit-app-install-helper'" "$page"
grep -Fq "['sudo','-n','/usr/local/sbin/msfixit-app-install-helper','install',\$appId]" "$page"
grep -Fq "Diese App ist für die aktuelle Lizenz nicht freigeschaltet" "$page"
grep -Fq 'www-data ALL=(root) NOPASSWD: /usr/local/sbin/msfixit-app-install-helper install at.msfixit.shopos.*' "$sudoers"
! grep -Eq '(shell_exec|system\(|passthru\(|`)' "$page"
! grep -Eq '(curl|wget|apt|dnf|yum|pacman)' "$page" "$sudoers"
printf 'PASS: Store install requests are authenticated, CSRF protected, explicitly confirmed and delegated without a shell to the narrow helper.\n'
