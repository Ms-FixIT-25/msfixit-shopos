#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/image/package/usr/share/msfixit-shopos/admin-console/public/index.php"
init="$root/image/package/usr/local/sbin/msfixit-admin-console-init"
site="$root/image/package/etc/nginx/sites-available/msfixit-shopos.conf"
snippet="$root/image/package/etc/nginx/snippets/msfixit-admin-console.conf"
unit="$root/image/package/etc/systemd/system/msfixit-admin-console-init.service"

php -l "$app"
bash -n "$init"
grep -Fq "session_regenerate_id(true)" "$app"
grep -Fq "hash_equals(csrfToken(), \$token)" "$app"
grep -Fq "password_verify" "$app"
grep -Fq "Cache-Control: no-store" "$app"
grep -Fq "authentication_required" "$app"
grep -Fq "allow 192.168.0.0/16" "$snippet"
grep -Fq "deny all" "$snippet"
grep -Fq "include snippets/msfixit-admin-console.conf;" "$site"
grep -Fq "fastcgi_pass unix:/run/php/msfixit-fpm.sock;" "$snippet"
grep -Fq "chmod 0640" "$init"
grep -Fq "chown root:www-data" "$init"
grep -Fq "ExecStart=/bin/bash /usr/local/sbin/msfixit-admin-console-init" "$unit"
if grep -Eqi "PASSWORD[[:space:]]*=[[:space:]]*['\"][^$]" "$app" "$init"; then
    echo "Hard-coded password detected." >&2
    exit 1
fi
printf 'PASS: admin console Phase 1 authentication, CSRF, local-network restriction and secret handling checks.\n'
