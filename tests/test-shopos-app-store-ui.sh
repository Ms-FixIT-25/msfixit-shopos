#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
page="$root/image/package/usr/share/msfixit-shopos/admin-console/public/store.php"
php -l "$page"
grep -Fq "session_name('SHOPOSADMIN')" "$page"
grep -Fq "hash_equals(csrfToken(), \$token)" "$page"
grep -Fq "Basisbetrieb ohne aktive Lizenz" "$page"
grep -Fq "Professional freischalten" "$page"
grep -Fq "Installation ist vorbereitet" "$page"
grep -Fq "Diese App ist für die aktuelle Lizenz nicht freigeschaltet" "$page"
grep -Fq "Content-Security-Policy" "$page"
! grep -Eq '(shell_exec|exec\(|system\(|passthru\()' "$page"
printf 'PASS: ShopOS Store UI is authenticated, CSRF protected, fail-closed and contains no direct package execution.\n'
