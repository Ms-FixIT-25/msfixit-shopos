#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

plugin=image/package/usr/share/msfixit-shopos/wordpress/msfixit-workspace.php
install_script=image/package/usr/local/sbin/msfixit-brand-shop

test -s "$plugin"
test -s docs/GOOGLE_WORKSPACE.md

if command -v php >/dev/null 2>&1; then
    php -l "$plugin" >/dev/null
fi

grep -Fq "office@msfixit.at" "$plugin"
grep -Fq "https://www.googleapis.com/auth/gmail.send" "$plugin"
grep -Fq "https://gmail.googleapis.com/gmail/v1/users/me/messages/send" "$plugin"
grep -Fq "https://oauth2.googleapis.com/token" "$plugin"
grep -Fq "https://openidconnect.googleapis.com/v1/userinfo" "$plugin"
grep -Fq "pre_wp_mail" "$plugin"
grep -Fq "manage_options" "$plugin"
grep -Fq "check_admin_referer" "$plugin"
grep -Fq "hash_equals" "$plugin"
grep -Fq "sodium_crypto_secretbox" "$plugin"
grep -Fq "msfixit_workspace_refresh_token_encrypted" "$plugin"
grep -Fq "Google Workspace ist nicht verbunden; die E-Mail wurde nicht versendet." "$plugin"
grep -Fq "msfixit-workspace.php" "$install_script"

if grep -Eq "auth/gmail\.read|auth/gmail\.modify|auth/drive|auth/calendar" "$plugin"; then
    echo "Workspace OAuth must remain limited to identity and Gmail send access." >&2
    exit 1
fi

if grep -Eq "get_option\('msfixit_workspace_(client_secret|refresh_token)'" "$plugin"; then
    echo "Workspace secrets must not be stored as plaintext options." >&2
    exit 1
fi

echo "Google Workspace OAuth mail checks passed."
