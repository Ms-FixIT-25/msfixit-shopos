#!/usr/bin/env bash
set -Eeuo pipefail

root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
plugin="$root/image/package/usr/share/msfixit-shopos/wordpress/msfixit-customer-auth.php"
style="$root/image/package/usr/share/msfixit-shopos/wordpress/assets/msfixit-customer-auth.css"
doc="$root/docs/CUSTOMER_AUTH.md"
install_script="$root/image/package/usr/local/sbin/msfixit-brand-shop"

for file in "$plugin" "$style" "$doc"; do
    test -s "$file"
done

php -l "$plugin" >/dev/null

grep -Fq "openid email profile" "$plugin"
grep -Fq "code_challenge_method' => 'S256'" "$plugin"
grep -Fq "msfixit_customer_auth_state_key" "$plugin"
grep -Fq "email_verified" "$plugin"
grep -Fq "_msfixit_google_sub" "$plugin"
grep -Fq "link_required" "$plugin"
grep -Fq "array_intersect(\$user->roles, ['administrator', 'shop_manager'])" "$plugin"
grep -Fq "wp_set_auth_cookie" "$plugin"
grep -Fq "add_rewrite_endpoint" "$plugin"
grep -Fq "wp_authenticate_user" "$plugin"
grep -Fq "hash_hmac('sha1'" "$plugin"
grep -Fq "wp_hash_password" "$plugin"
grep -Fq "wp_check_password" "$plugin"
grep -Fq "destroy_others" "$plugin"
grep -Fq "msfixit-customer-auth.php" "$install_script"
grep -Fq "msfixit-customer-auth.css" "$install_script"
grep -Fq "Existing local accounts are never linked solely" "$doc"

if grep -Eqi "auth/gmail|auth/drive|auth/calendar|auth/contacts|mail\.google\.com" "$plugin"; then
    echo "Customer Google sign-in must not request Workspace data scopes." >&2
    exit 1
fi

if grep -Eq "update_user_meta\([^,]+, '_msfixit_totp_secret(_encrypted)?', \$secret\)" "$plugin"; then
    echo "TOTP secrets must not be stored as plaintext user metadata." >&2
    exit 1
fi

if grep -Eq "update_user_meta\([^,]+, '_msfixit_recovery_(codes|plain)'" "$plugin"; then
    echo "Recovery codes must never be stored as plaintext user metadata." >&2
    exit 1
fi

if grep -Fq "get_user_by('email', \$email);" "$plugin" && ! grep -Fq "msfixit_customer_google_error_redirect('link_required'" "$plugin"; then
    echo "Existing matching emails must require deliberate account linking." >&2
    exit 1
fi

printf 'Customer authentication security checks passed.\n'
