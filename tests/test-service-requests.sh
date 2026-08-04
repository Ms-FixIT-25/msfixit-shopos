#!/usr/bin/env bash
set -Eeuo pipefail

root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
plugin="$root/image/package/usr/share/msfixit-shopos/wordpress/msfixit-service-requests.php"
provision="$root/image/package/usr/share/msfixit-shopos/wordpress/msfixit-service-provision.php"
style="$root/image/package/usr/share/msfixit-shopos/wordpress/assets/msfixit-service-requests.css"
doc="$root/docs/SERVICE_REQUESTS.md"

for file in "$plugin" "$provision" "$style" "$doc"; do
    test -s "$file"
done

php -l "$plugin" >/dev/null
php -l "$provision" >/dev/null

grep -Fq "'public' => false" "$plugin"
grep -Fq "'publicly_queryable' => false" "$plugin"
grep -Fq "'show_in_rest' => false" "$plugin"
grep -Fq "check_admin_referer('msfixit_service_request'" "$plugin"
grep -Fq 'msfixit-service-honeypot' "$plugin"
grep -Fq "msfixit_service_rate_limited('submit', 5" "$plugin"
grep -Fq "password_hash(\$secret, PASSWORD_DEFAULT)" "$plugin"
grep -Fq 'password_verify($secret, $hash)' "$plugin"
grep -Fq "get_option('msfixit_service_public_enabled', 'no') === 'yes'" "$plugin"
grep -Fq "post_status !== 'publish'" "$plugin"
grep -Fq "header('Referrer-Policy: no-referrer')" "$plugin"
grep -Fq "header('Cache-Control: private, no-store, max-age=0')" "$plugin"
grep -Fq "\$robots['noindex'] = true" "$plugin"
grep -Fq "\$robots['noarchive'] = true" "$plugin"
grep -Fq "update_option('msfixit_service_public_enabled', 'no')" "$provision"
grep -Fq '[msfixit_service_request_form]' "$provision"
grep -Fq '[msfixit_service_status]' "$provision"
grep -Fq 'creates no chargeable order' "$doc"

if grep -Eqi 'type=["'\'' ]*file|wp_handle_upload|media_handle_upload' "$plugin"; then
    echo 'Service portal must not accept file uploads.' >&2
    exit 1
fi

if grep -Eqi 'name=["'\'' ]*(password|pin|credit_card|card_number)' "$plugin"; then
    echo 'Service portal must not collect passwords, PINs or card numbers.' >&2
    exit 1
fi

bash "$root/tests/test-workspace-mail.sh"
printf 'Service request security checks passed.\n'
