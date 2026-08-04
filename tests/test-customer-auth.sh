#!/usr/bin/env bash
set -Eeuo pipefail

root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
plugin="$root/image/package/usr/share/msfixit-shopos/wordpress/msfixit-customer-auth.php"
modules="$root/image/package/usr/share/msfixit-shopos/wordpress/msfixit-customer-auth"
style="$root/image/package/usr/share/msfixit-shopos/wordpress/assets/msfixit-customer-auth.css"
doc="$root/docs/CUSTOMER_AUTH.md"
install_script="$root/image/package/usr/local/sbin/msfixit-brand-shop"
combined="$(mktemp)"
trap 'rm -f "$combined"' EXIT

for file in "$plugin" "$style" "$doc" "$modules/google.php" "$modules/flow.php" "$modules/totp.php" "$modules/account.php" "$modules/admin.php"; do
    test -s "$file"
done

for file in "$plugin" "$modules"/*.php; do
    php -l "$file" >/dev/null
    cat "$file" >> "$combined"
done

grep -Fq "openid email profile" "$combined"
grep -Fq "code_challenge_method' => 'S256'" "$combined"
grep -Fq "msfixit_customer_auth_state_key" "$combined"
grep -Fq "browser_hash" "$combined"
grep -Fq "MSFIXIT_CUSTOMER_GOOGLE_FLOW_COOKIE" "$combined"
grep -Fq "'httponly' => true" "$combined"
grep -Fq "'samesite' => 'Lax'" "$combined"
grep -Fq "hash_equals((string) \$flow['browser_hash']" "$combined"
grep -Fq "email_verified" "$combined"
grep -Fq "_msfixit_google_sub" "$combined"
grep -Fq "link_required" "$combined"
grep -Fq "array_intersect(\$user->roles, ['administrator', 'shop_manager'])" "$combined"
grep -Fq "wp_set_auth_cookie" "$combined"
grep -Fq "add_rewrite_endpoint" "$combined"
grep -Fq "wp_authenticate_user" "$combined"
grep -Fq "hash_hmac('sha1'" "$combined"
grep -Fq "wp_hash_password" "$combined"
grep -Fq "wp_check_password" "$combined"
grep -Fq "destroy_others" "$combined"
grep -Fq "_msfixit_google_created" "$combined"
grep -Fq "_msfixit_local_password_ready" "$combined"
grep -Fq "msfixit-customer-auth.php" "$install_script"
grep -Fq "msfixit-customer-auth.css" "$install_script"
grep -Fq "Existing local accounts are never linked solely" "$doc"

if grep -Eqi "auth/gmail|auth/drive|auth/calendar|auth/contacts|mail\.google\.com" "$combined"; then
    echo "Customer Google sign-in must not request Workspace data scopes." >&2
    exit 1
fi

if grep -Eq "update_user_meta\([^,]+, '_msfixit_totp_secret(_encrypted)?', \$secret\)" "$combined"; then
    echo "TOTP secrets must not be stored as plaintext user metadata." >&2
    exit 1
fi

if grep -Eq "update_user_meta\([^,]+, '_msfixit_recovery_(codes|plain)'" "$combined"; then
    echo "Recovery codes must never be stored as plaintext user metadata." >&2
    exit 1
fi

if grep -Fq "get_user_by('email', \$email);" "$combined" && ! grep -Fq "msfixit_customer_google_error_redirect('link_required'" "$combined"; then
    echo "Existing matching emails must require deliberate account linking." >&2
    exit 1
fi

printf 'Customer authentication security checks passed.\n'
