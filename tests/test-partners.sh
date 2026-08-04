#!/usr/bin/env bash
set -Eeuo pipefail
set -x

: "${MYSQL_PWD:?MYSQL_PWD is required}"
readonly root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
readonly cli="${root}/image/package/usr/local/sbin/msfixit-partners"
readonly schema="${root}/image/package/usr/share/msfixit-shopos/partners/schema.sql"
readonly db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_catalog)

"${db[@]}" < "$schema"

install -d -m 0750 /etc/msfixit-shopos /data/partners/evidence
cat > /etc/msfixit-shopos/catalog.env <<EOF_ENV
CATALOG_DB_HOST=127.0.0.1
CATALOG_DB_PORT=3306
CATALOG_DB_NAME=shopos_catalog
CATALOG_DB_USER=root
CATALOG_DB_PASSWORD=${MYSQL_PWD}
EOF_ENV
chmod 0600 /etc/msfixit-shopos/catalog.env

printf 'iFixit Pro account approval evidence\n' > /data/partners/evidence/ifixit-pro.txt
printf 'FRITZ Business programme evidence\n' > /data/partners/evidence/fritz-status.txt
printf 'FRITZ approved marketing asset evidence\n' > /data/partners/evidence/fritz-logo-rights.txt

php "$cli" verify \
    ifixit-pro \
    'iFixit Pro' \
    none \
    /data/partners/evidence/ifixit-pro.txt \
    ci \
    'iFixit Pro Mitglied'
php "$cli" enable ifixit-pro ci

test "$("${db[@]}" --batch --skip-column-names --execute="SELECT public_enabled FROM partner_profiles WHERE partner_code='ifixit-pro'")" = 1
test "$("${db[@]}" --batch --skip-column-names --execute="SELECT logo_mode FROM partner_profiles WHERE partner_code='ifixit-pro'")" = none

php "$cli" verify \
    fritz-business-at \
    'FRITZ! Business-Partnerprogramm Österreich' \
    2020-12-31 \
    /data/partners/evidence/fritz-status.txt \
    ci \
    'Teilnahme am FRITZ! Business-Partnerprogramm Österreich'
if php "$cli" enable fritz-business-at ci; then
    echo 'Expired partner status was incorrectly enabled.' >&2
    exit 1
fi

php "$cli" verify \
    fritz-business-at \
    'FRITZ! Business-Partnerprogramm Österreich' \
    2099-12-31 \
    /data/partners/evidence/fritz-status.txt \
    ci \
    'Teilnahme am FRITZ! Business-Partnerprogramm Österreich'

if php "$cli" logo fritz-business-at http://example.invalid/fritz.svg /data/partners/evidence/fritz-logo-rights.txt ci; then
    echo 'Insecure partner logo URL was incorrectly accepted.' >&2
    exit 1
fi
php "$cli" logo fritz-business-at https://cdn.example.invalid/fritz-approved.svg /data/partners/evidence/fritz-logo-rights.txt ci
php "$cli" enable fritz-business-at ci

test "$("${db[@]}" --batch --skip-column-names --execute="SELECT public_enabled FROM partner_profiles WHERE partner_code='fritz-business-at'")" = 1
test "$("${db[@]}" --batch --skip-column-names --execute="SELECT logo_rights_verified FROM partner_profiles WHERE partner_code='fritz-business-at'")" = 1

php "$cli" disable fritz-business-at ci evidence-test
printf 'tampered\n' >> /data/partners/evidence/fritz-status.txt
if php "$cli" enable fritz-business-at ci; then
    echo 'Tampered membership evidence was incorrectly accepted.' >&2
    exit 1
fi

if "${db[@]}" --execute="UPDATE partner_profiles SET partner_code='changed' WHERE partner_code='ifixit-pro'"; then
    echo 'Partner identity mutation was not blocked.' >&2
    exit 1
fi
if "${db[@]}" --execute="DELETE FROM partner_profiles WHERE partner_code='ifixit-pro'"; then
    echo 'Partner profile deletion was not blocked.' >&2
    exit 1
fi

audit_count="$("${db[@]}" --batch --skip-column-names --execute="SELECT COUNT(*) FROM partner_profile_audit")"
test "$audit_count" -ge 6

php "$cli" list | jq -e 'map(select(.partner_code == "ifixit-pro")) | length == 1'

echo 'Partner profile and public-claim integration test passed.'
