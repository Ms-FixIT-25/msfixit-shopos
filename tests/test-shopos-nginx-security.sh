#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/image/package/etc/nginx/sites-available/msfixit-shopos.conf"

test -s "$config"

deny_line="$(grep -nE 'location[[:space:]]+~\*[[:space:]]+/(\?:uploads\|files|\(\?:uploads\|files\)).*\\\.php' "$config" | head -n1 | cut -d: -f1 || true)"
if [ -z "$deny_line" ]; then
    deny_line="$(grep -nF 'location ~* /(?:uploads|files)/.*\.php$ {' "$config" | head -n1 | cut -d: -f1 || true)"
fi
generic_line="$(grep -nF 'location ~ \.php$ {' "$config" | head -n1 | cut -d: -f1 || true)"
hidden_line="$(grep -nF 'location ~ /\. {' "$config" | head -n1 | cut -d: -f1 || true)"

[ -n "$deny_line" ] || { echo 'Missing deny rule for PHP in writable upload/file paths.' >&2; exit 1; }
[ -n "$generic_line" ] || { echo 'Missing generic PHP-FPM location.' >&2; exit 1; }
[ -n "$hidden_line" ] || { echo 'Missing hidden-path deny rule.' >&2; exit 1; }

if [ "$deny_line" -ge "$generic_line" ]; then
    echo 'Upload/file PHP deny must be declared before generic PHP-FPM handling.' >&2
    exit 1
fi
if [ "$hidden_line" -ge "$generic_line" ]; then
    echo 'Hidden-path deny must be declared before generic PHP-FPM handling.' >&2
    exit 1
fi

grep -A3 -F 'location ~* /(?:uploads|files)/.*\.php$ {' "$config" | grep -Fq 'deny all;'
grep -A8 -F 'location ~ \.php$ {' "$config" | grep -Fq 'fastcgi_pass unix:/run/php/msfixit-fpm.sock;'

printf 'PASS: Nginx deny locations precede the generic PHP handler, preventing uploaded PHP execution.\n'
