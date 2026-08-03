#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"

db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_catalog)
"${db[@]}" < image/package/usr/share/msfixit-shopos/catalog/schema.sql
"${db[@]}" < image/package/usr/share/msfixit-shopos/catalog/guards.sql

cat > /tmp/catalog.env <<'EOF_CATALOG'
CATALOG_DB_HOST=127.0.0.1
CATALOG_DB_PORT=3306
CATALOG_DB_NAME=shopos_catalog
CATALOG_DB_USER=root
CATALOG_DB_PASSWORD=shopos-ci-root
EOF_CATALOG
sudo install -d -m 0750 /etc/msfixit-shopos
sudo install -m 0600 /tmp/catalog.env /etc/msfixit-shopos/catalog.env

article="$(sudo php image/package/usr/local/sbin/msfixit-catalog create 'CI Test Product' simple)"
test "$article" = MF-00000001

sudo php image/package/usr/local/sbin/msfixit-catalog map "$article" supplier:ci SUP-100 primary
sudo php image/package/usr/local/sbin/msfixit-catalog offer "$article" ci SUP-100 42.50 EUR 7 available
sudo php image/package/usr/local/sbin/msfixit-catalog channel "$article" woocommerce 384 "$article" active
sudo php image/package/usr/local/sbin/msfixit-catalog show "$article" | jq -e '.article_number == "MF-00000001"'
sudo php image/package/usr/local/sbin/msfixit-catalog resolve supplier:ci SUP-100 | jq -e '.article_number == "MF-00000001"'
sudo php image/package/usr/local/sbin/msfixit-catalog export-csv /tmp/article-master.csv
grep -q 'MF-00000001' /tmp/article-master.csv

if "${db[@]}" --execute="UPDATE catalog_products SET article_number='MF-99999999' WHERE article_number='MF-00000001'"; then
  echo 'Article-number immutability trigger did not block an update.' >&2
  exit 1
fi

if "${db[@]}" --execute="DELETE FROM catalog_products WHERE article_number='MF-00000001'"; then
  echo 'Archive-only trigger did not block a delete.' >&2
  exit 1
fi

trigger_count="$("${db[@]}" --batch --skip-column-names --execute="SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='shopos_catalog'")"
test "$trigger_count" -ge 5

echo 'Article-master integration test passed.'
