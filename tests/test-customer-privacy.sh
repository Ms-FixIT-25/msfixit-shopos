#!/usr/bin/env bash
set -Eeuo pipefail

root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
loader="$root/image/package/usr/share/msfixit-shopos/wordpress/msfixit-customer-auth.php"
privacy="$root/image/package/usr/share/msfixit-shopos/wordpress/msfixit-customer-auth/privacy.php"
style="$root/image/package/usr/share/msfixit-shopos/wordpress/assets/msfixit-customer-auth.css"
doc="$root/docs/CUSTOMER_PRIVACY.md"

for file in "$loader" "$privacy" "$style" "$doc"; do
    test -s "$file"
done

php -l "$privacy" >/dev/null

grep -Fq "'privacy.php'" "$loader"
grep -Fq "MSFIXIT_CUSTOMER_PRIVACY_ENDPOINT" "$privacy"
grep -Fq "woocommerce_account_" "$privacy"
grep -Fq "wp_privacy_personal_data_exporters" "$privacy"
grep -Fq "processing_categories" "$privacy"
grep -Fq "legal_basis" "$privacy"
grep -Fq "recipients" "$privacy"
grep -Fq "retention" "$privacy"
grep -Fq "automated_decisions" "$privacy"
grep -Fq "hash('sha256', \$token)" "$privacy"
grep -Fq "MSFIXIT_CUSTOMER_EXPORT_TOKEN_TTL" "$privacy"
grep -Fq "personal_data_export_requested" "$privacy"
grep -Fq "personal_data_export_downloaded" "$privacy"
grep -Fq "Content-Type: application/json" "$privacy"
grep -Fq "X-Robots-Tag: noindex, nofollow, noarchive" "$privacy"
grep -Fq "Referrer-Policy: no-referrer" "$privacy"
grep -Fq "JSON_PRETTY_PRINT" "$privacy"
grep -Fq "office_payment_allocations" "$privacy"
grep -Fq "_msfixit_service_privacy_consent_at" "$privacy"
grep -Fq "Der Link ist 24 Stunden gültig" "$privacy"
grep -Fq "fails closed" "$doc"

if grep -Eq "['\"](_msfixit_totp_secret_encrypted|_msfixit_recovery_hashes|_msfixit_service_secret_hash)['\"]\s*=>" "$privacy"; then
    echo "Privacy export must not serialize credential or service-secret metadata." >&2
    exit 1
fi

if grep -Fq "raw_payload_json" "$privacy"; then
    echo "Privacy export must not include raw payment-provider payloads." >&2
    exit 1
fi

if grep -Eqi "OFFICE_DB_PASSWORD|google_client_secret|refresh_token|access_token" "$privacy"; then
    echo "Privacy export module must not read or expose infrastructure credentials." >&2
    exit 1
fi

printf 'Customer privacy and personal-data export checks passed.\n'
