#!/usr/bin/env bash
set -Eeuo pipefail

root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export MYSQL_PWD="${MYSQL_PWD:-shopos-ci-root}"
db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_catalog)

"${db[@]}" < "$root/image/package/usr/share/msfixit-shopos/catalog/schema.sql"
"${db[@]}" < "$root/image/package/usr/share/msfixit-shopos/catalog/guards.sql"
"${db[@]}" < "$root/image/package/usr/share/msfixit-shopos/also/schema.sql"
"${db[@]}" < "$root/image/package/usr/share/msfixit-shopos/also/content.sql"
"${db[@]}" < "$root/image/package/usr/share/msfixit-shopos/also/content-guards.sql"

install -d -m 0750 /etc/msfixit-shopos /data/suppliers/also/content
cat > /etc/msfixit-shopos/catalog.env <<'EOF_DB'
CATALOG_DB_HOST=127.0.0.1
CATALOG_DB_PORT=3306
CATALOG_DB_NAME=shopos_catalog
CATALOG_DB_USER=root
CATALOG_DB_PASSWORD=shopos-ci-root
EOF_DB
chmod 0600 /etc/msfixit-shopos/catalog.env

cat > /etc/msfixit-shopos/also.env <<'EOF_CONFIG'
ALSO_ENABLED=no
ALSO_SUPPLIER_CODE=also-at
ALSO_CONTENT_ENABLED=no
ALSO_CONTENT_PACKAGE=standard
ALSO_CONTENT_LANGUAGE=de-AT
ALSO_CONTENT_MEDIA_MODE=remote_only
ALSO_CONTENT_ALLOW_TEXT_IMPORT=yes
ALSO_ALLOW_REMOTE_IMAGES=yes
ALSO_ALLOW_REMOTE_DOCUMENTS=yes
ALSO_ALLOW_LOCAL_IMAGE_CACHE=no
ALSO_ALLOW_LOCAL_DOCUMENT_CACHE=no
ALSO_CONTENT_MAX_ROWS_PER_IMPORT=1000
ALSO_CONTENT_LIST_SEPARATOR=|
ALSO_CONTENT_FEED_ENCODING=UTF-8
ALSO_CONTENT_FEED_DELIMITER=semicolon
ALSO_CONTENT_FIELD_SUPPLIER_SKU=SupplierSKU
ALSO_CONTENT_FIELD_STANDARD_DESCRIPTION=StandardDescription
ALSO_CONTENT_FIELD_MARKETING_DESCRIPTION=MarketingDescription
ALSO_CONTENT_FIELD_SELLING_POINTS=SellingPoints
ALSO_CONTENT_FIELD_FEATURES=Features
ALSO_CONTENT_FIELD_SPECIFICATIONS=Specifications
ALSO_CONTENT_FIELD_IMAGE_URLS=ImageURLs
ALSO_CONTENT_FIELD_DOCUMENT_URLS=DocumentURLs
ALSO_CONTENT_FIELD_DATASHEET_URL=DatasheetURL
ALSO_CONTENT_FIELD_ACCESSORY_SKUS=AccessorySKUs
EOF_CONFIG
chmod 0600 /etc/msfixit-shopos/also.env

"${db[@]}" --execute="
INSERT INTO supplier_feed_items
(supplier_code,supplier_sku,product_name,purchase_price,currency,stock_status,source_payload_json,source_sha256)
VALUES
('also-at','ALSO-CABLE-1','USB-C Kabel 2 m',8.50,'EUR','available','{}',REPEAT('a',64)),
('also-at','ALSO-CABLE-2','USB-C Kabel 1 m',6.50,'EUR','available','{}',REPEAT('b',64));"

feed=/tmp/also-content.csv
cat > "$feed" <<'EOF_FEED'
SupplierSKU;StandardDescription;MarketingDescription;SellingPoints;Features;Specifications;ImageURLs;DocumentURLs;DatasheetURL;AccessorySKUs
ALSO-CABLE-1;USB-C Kabel für Laden und Daten.;Robustes USB-C Kabel für Notebook und Smartphone.;60 W|2 Meter|USB-C beidseitig;geflochten|schwarz;{"Anschluss":"USB-C auf USB-C","Länge":"2 m","Leistung":"60 W"};https://cdn.example.test/cable-front.jpg|https://cdn.example.test/cable-detail.jpg;https://cdn.example.test/manual.pdf;https://cdn.example.test/datasheet.pdf;ALSO-CABLE-2
EOF_FEED

php "$root/image/package/usr/local/sbin/msfixit-also-content" import-file "$feed" \
  | jq -e '.status == "completed" and .statistics.accepted == 1 and .statistics.new == 1'

# The same feed is idempotent.
php "$root/image/package/usr/local/sbin/msfixit-also-content" import-file "$feed" \
  | jq -e '.status == "duplicate"'

# Imported content cannot be approved before the account contract is verified.
if php "$root/image/package/usr/local/sbin/msfixit-also-content" approve ALSO-CABLE-1 ci-reviewer; then
    echo 'Unverified ALSO content was approved.' >&2
    exit 1
fi

php "$root/image/package/usr/local/sbin/msfixit-also-content" contract standard ci-reviewer 'CI test contract'
php "$root/image/package/usr/local/sbin/msfixit-also-content" approve ALSO-CABLE-1 ci-reviewer

"${db[@]}" --batch --skip-column-names --execute="
SELECT CONCAT(review_status,':',content_package,':',JSON_LENGTH(selling_points_json))
FROM supplier_content_items
WHERE supplier_code='also-at' AND supplier_sku='ALSO-CABLE-1';" | grep -qx 'approved:standard:3'

image_count="$("${db[@]}" --batch --skip-column-names --execute="
SELECT COUNT(*) FROM supplier_content_assets a
JOIN supplier_content_items i ON i.id=a.content_item_id
WHERE i.supplier_sku='ALSO-CABLE-1' AND a.asset_type='image' AND a.approval_status='approved';")"
test "$image_count" -eq 2

document_count="$("${db[@]}" --batch --skip-column-names --execute="
SELECT COUNT(*) FROM supplier_content_assets a
JOIN supplier_content_items i ON i.id=a.content_item_id
WHERE i.supplier_sku='ALSO-CABLE-1' AND a.asset_type='document' AND a.approval_status='approved';")"
test "$document_count" -eq 2

relation_count="$("${db[@]}" --batch --skip-column-names --execute="
SELECT COUNT(*) FROM supplier_content_relations
WHERE source_supplier_sku='ALSO-CABLE-1' AND target_supplier_sku='ALSO-CABLE-2' AND active=1;")"
test "$relation_count" -eq 1

# Local caching cannot be enabled by a configuration or database mistake.
if "${db[@]}" --execute="
UPDATE supplier_content_profiles SET allow_local_image_cache=1 WHERE supplier_code='also-at';"; then
    echo 'Local image caching guard did not reject the update.' >&2
    exit 1
fi

# A changed licensed text reopens review instead of silently replacing approved content.
changed=/tmp/also-content-changed.csv
sed 's/Robustes USB-C Kabel/Überarbeiteter lizenzierter Text/' "$feed" > "$changed"
php "$root/image/package/usr/local/sbin/msfixit-also-content" import-file "$changed" \
  | jq -e '.status == "completed" and .statistics.updated == 1'

status="$("${db[@]}" --batch --skip-column-names --execute="
SELECT CONCAT(review_status,':',review_reason)
FROM supplier_content_items
WHERE supplier_code='also-at' AND supplier_sku='ALSO-CABLE-1';")"
test "$status" = 'pending:supplier_content_changed'

change_count="$("${db[@]}" --batch --skip-column-names --execute="
SELECT COUNT(*) FROM supplier_content_changes WHERE field_name='marketing_description';")"
test "$change_count" -ge 1

# Insecure linked media is rejected.
insecure=/tmp/also-content-insecure.csv
sed 's#https://cdn.example.test/cable-front.jpg#http://cdn.example.test/cable-front.jpg#' "$feed" > "$insecure"
if php "$root/image/package/usr/local/sbin/msfixit-also-content" import-file "$insecure"; then
    echo 'Insecure content URL was accepted.' >&2
    exit 1
fi

# The connector stores URLs and metadata only; it does not cache supplier media.
if find /data/suppliers/also/content -type f | grep -q .; then
    echo 'The content importer cached linked supplier files locally.' >&2
    exit 1
fi

trigger_count="$("${db[@]}" --batch --skip-column-names --execute="
SELECT COUNT(*) FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA='shopos_catalog' AND TRIGGER_NAME LIKE 'trg_supplier_content%';")"
test "$trigger_count" -ge 7

echo 'Licensed ALSO content integration test passed.'
