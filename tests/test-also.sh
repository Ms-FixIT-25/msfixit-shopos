#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"

db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_catalog)
"${db[@]}" < image/package/usr/share/msfixit-shopos/also/schema.sql

sudo install -d -m 0750 /etc/msfixit-shopos
sudo install -d -m 0750 /data/suppliers/also/{incoming,archive,quarantine,reports}

cat > /tmp/also.env <<'EOF_CONFIG'
AT_PILOT_ENABLED=yes
AT_PILOT_COUNTRY=AT
AT_PILOT_MAX_APPROVED_PRODUCTS=30
AT_PILOT_SINGLE_SUPPLIER=also-at
AT_PILOT_MANUAL_PRODUCT_APPROVAL=yes
AT_PILOT_MANUAL_ORDER_RELEASE=yes
AT_PILOT_AUTO_PUBLISH=no
AT_PILOT_AUTO_SUPPLIER_ORDER=no
AT_PILOT_PRICING_APPROVED=no
AT_PILOT_TARGET_GROSS_MARGIN_PERCENT=
AT_PILOT_PRICE_CHANGE_REVIEW_PERCENT=5
AT_PILOT_STOCK_SAFETY_QUANTITY=2
AT_PILOT_REQUIRE_POSITIVE_STOCK=yes
ALSO_ENABLED=no
ALSO_SUPPLIER_CODE=also-at
ALSO_SOURCE_MODE=sftp_csv
ALSO_AUTO_UPDATE_EXISTING_OFFERS=yes
ALSO_ALLOW_MARKETING_TEXT=no
ALSO_ALLOW_LOCAL_IMAGE_CACHE=no
ALSO_CONTENT_LICENSE=none
ALSO_MAX_ROWS_PER_IMPORT=100
ALSO_MAX_NEW_ITEMS_PER_IMPORT=50
ALSO_FEED_ENCODING=UTF-8
ALSO_FEED_DELIMITER=semicolon
ALSO_FIELD_SUPPLIER_SKU=SupplierSKU
ALSO_FIELD_MANUFACTURER=Manufacturer
ALSO_FIELD_MANUFACTURER_SKU=ManufacturerSKU
ALSO_FIELD_GTIN=EAN
ALSO_FIELD_PRODUCT_NAME=ProductName
ALSO_FIELD_SHORT_DESCRIPTION=ShortDescription
ALSO_FIELD_MARKETING_DESCRIPTION=MarketingDescription
ALSO_FIELD_CATEGORY=Category
ALSO_FIELD_PURCHASE_PRICE=PurchasePrice
ALSO_FIELD_CURRENCY=Currency
ALSO_FIELD_STOCK_QUANTITY=Stock
ALSO_FIELD_STOCK_STATUS=Availability
ALSO_FIELD_LEAD_TIME_DAYS=LeadTimeDays
ALSO_FIELD_IMAGE_URL=ImageURL
ALSO_FIELD_DATASHEET_URL=DatasheetURL
EOF_CONFIG
sudo install -m 0640 -o root -g root /tmp/also.env /etc/msfixit-shopos/also.env

cat > /tmp/also-feed-1.csv <<'EOF_FEED'
SupplierSKU;Manufacturer;ManufacturerSKU;EAN;ProductName;ShortDescription;MarketingDescription;Category;PurchasePrice;Currency;Stock;Availability;LeadTimeDays;ImageURL;DatasheetURL
ALSO-100;ExampleTech;EX-100;4000000000100;USB-C Dock;Dockingstation;Lizenzierter Text;Docking;99,90;EUR;12;verfügbar;1;https://content.example/image.jpg;https://content.example/data.pdf
ALSO-INVALID;ExampleTech;EX-200;4000000000200;Ungültiger Artikel;;;Docking;0;EUR;0;nicht verfügbar;5;;
EOF_FEED

before_products="$("${db[@]}" --batch --skip-column-names --execute='SELECT COUNT(*) FROM catalog_products')"
sudo php image/package/usr/local/sbin/msfixit-also import-file /tmp/also-feed-1.csv \
  | tee /tmp/also-import-1.json
jq -e '.status == "completed" and .stats.total == 2 and .stats.accepted == 1 and .stats.quarantined == 1' /tmp/also-import-1.json

after_products="$("${db[@]}" --batch --skip-column-names --execute='SELECT COUNT(*) FROM catalog_products')"
test "$before_products" = "$after_products"

test "$("${db[@]}" --batch --skip-column-names --execute="SELECT review_status FROM supplier_feed_items WHERE supplier_sku='ALSO-100'")" = new
test "$("${db[@]}" --batch --skip-column-names --execute="SELECT review_status FROM supplier_feed_items WHERE supplier_sku='ALSO-INVALID'")" = quarantined
test "$("${db[@]}" --batch --skip-column-names --execute="SELECT woocommerce_product_id IS NULL FROM supplier_feed_items WHERE supplier_sku='ALSO-100'")" = 1

sudo php image/package/usr/local/sbin/msfixit-also import-file /tmp/also-feed-1.csv \
  | jq -e '.status == "duplicate"'

cat > /tmp/also-feed-2.csv <<'EOF_FEED'
SupplierSKU;Manufacturer;ManufacturerSKU;EAN;ProductName;ShortDescription;MarketingDescription;Category;PurchasePrice;Currency;Stock;Availability;LeadTimeDays;ImageURL;DatasheetURL
ALSO-100;ExampleTech;EX-100;4000000000100;USB-C Dock;Dockingstation;Lizenzierter Text;Docking;119,90;EUR;8;verfügbar;2;https://content.example/image.jpg;https://content.example/data.pdf
EOF_FEED
sudo php image/package/usr/local/sbin/msfixit-also import-file /tmp/also-feed-2.csv \
  | tee /tmp/also-import-2.json
jq -e '.status == "completed" and .stats.updated == 1' /tmp/also-import-2.json

test "$("${db[@]}" --batch --skip-column-names --execute="SELECT purchase_price FROM supplier_feed_items WHERE supplier_sku='ALSO-100'")" = 119.9000
test "$("${db[@]}" --batch --skip-column-names --execute="SELECT stock_quantity FROM supplier_feed_items WHERE supplier_sku='ALSO-100'")" = 8.000
test "$("${db[@]}" --batch --skip-column-names --execute="SELECT COUNT(*) FROM supplier_feed_changes WHERE field_name='purchase_price' AND requires_review=1")" = 1

sudo php image/package/usr/local/sbin/msfixit-also export-review /tmp/also-review.csv
 grep -q 'ALSO-100' /tmp/also-review.csv

sudo php image/package/usr/local/sbin/msfixit-also status \
  | jq -e '.pilot_enabled == true and .pilot_country == "AT" and .also_enabled == false and .auto_publish == false and .auto_supplier_order == false'

sudo php image/package/usr/local/sbin/msfixit-also sync | jq -e '.status == "disabled"'
sudo php image/package/usr/local/sbin/msfixit-also release-order 4711 119.90 ci \
  | jq -e '.status == "released_for_manual_purchase" and .supplier_order_sent == false'
test "$("${db[@]}" --batch --skip-column-names --execute="SELECT release_status FROM pilot_order_releases WHERE source_order_id='4711'")" = released

first_product="$("${db[@]}" --batch --skip-column-names --execute='SELECT id FROM catalog_products ORDER BY article_number LIMIT 1')"
second_article="$(sudo php image/package/usr/local/sbin/msfixit-catalog create 'Second CI Product' simple)"
second_product="$("${db[@]}" --batch --skip-column-names --execute="SELECT id FROM catalog_products WHERE article_number='${second_article}'")"
"${db[@]}" --execute="UPDATE supplier_feed_items SET linked_product_id='${first_product}' WHERE supplier_sku='ALSO-100'"
if "${db[@]}" --execute="UPDATE supplier_feed_items SET linked_product_id='${second_product}' WHERE supplier_sku='ALSO-100'"; then
  echo 'Supplier feed reassignment guard did not block a product change.' >&2
  exit 1
fi

echo 'ALSO Austria pilot connector integration test passed.'
