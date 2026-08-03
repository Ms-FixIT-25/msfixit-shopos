#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"
: "${GITHUB_WORKSPACE:=$(pwd)}"

root_db=(mariadb --host=127.0.0.1 --port=3306 --user=root)
"${root_db[@]}" --execute="DROP DATABASE IF EXISTS shopos_office; CREATE DATABASE shopos_office CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
office_db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_office)
"${office_db[@]}" < image/package/usr/share/msfixit-shopos/office/schema.sql
"${office_db[@]}" < image/package/usr/share/msfixit-shopos/office/operational.sql

cat > /tmp/office.env <<'EOF_OFFICE'
OFFICE_DB_HOST=127.0.0.1
OFFICE_DB_PORT=3306
OFFICE_DB_NAME=shopos_office
OFFICE_DB_USER=root
OFFICE_DB_PASSWORD=shopos-ci-root
EOF_OFFICE

cat > /tmp/business.env <<'EOF_BUSINESS'
BUSINESS_CONFIG_APPROVED=yes
BUSINESS_NAME=Ms. FixIT
BUSINESS_LEGAL_NAME=Ms. FixIT CI Test
BUSINESS_OWNER_NAME=CI
BUSINESS_STREET=Teststraße 1
BUSINESS_POSTCODE=5020
BUSINESS_CITY=Salzburg
BUSINESS_COUNTRY=AT
BUSINESS_EMAIL=ci@example.invalid
BUSINESS_PHONE=+430000000
BUSINESS_WEBSITE=https://example.invalid
BUSINESS_TAX_NUMBER=CI-TAX
BUSINESS_VAT_ID=
BUSINESS_IBAN=AT000000000000000000
BUSINESS_BIC=TESTAT00
DEFAULT_TAX_MODE=at_small_business_exempt
TAX_MODE_AT=at_small_business_exempt
TAX_MODE_DE=review_required
TAX_MODE_CH=review_required
SMALL_BUSINESS_NOTICE=Umsatzsteuerbefreit aufgrund der Kleinunternehmerregelung.
INVOICE_PREFIX=RE
CREDIT_NOTE_PREFIX=GU
DELIVERY_NOTE_PREFIX=LS
REMINDER_PREFIX=MA
SHIPMENT_PREFIX=VS
INVOICE_PAYMENT_DAYS=0
INVOICE_LANGUAGE=de_AT
INVOICE_CURRENCY=EUR
AUTO_FINALIZE_INVOICES=no
AUTO_FINALIZE_DELIVERY_NOTES=no
AUTO_SEND_INVOICES=no
AUTO_SEND_REMINDERS=no
AUTO_PRINT_INVOICES=no
AUTO_PRINT_DELIVERY_NOTES=no
AUTO_PRINT_LABELS=no
DUNNING_ENABLED=yes
DUNNING_AUTO_CREATE_FRIENDLY_REMINDER=yes
DUNNING_REQUIRE_APPROVAL_FROM_LEVEL=1
PROSALDO_EXPORT_ENABLED=yes
PROSALDO_EXPORT_PATH=/data/office/exports/prosaldo
PROSALDO_CONTACT_NUMBER_PREFIX=K
EOF_BUSINESS

sudo install -d -m 0750 /etc/msfixit-shopos /usr/share/msfixit-shopos /data/office
sudo install -m 0600 /tmp/office.env /etc/msfixit-shopos/office.env
sudo install -m 0600 /tmp/office.env /etc/msfixit-shopos/office-worker.env
sudo install -m 0640 /tmp/business.env /etc/msfixit-shopos/business.env
sudo rm -rf /usr/share/msfixit-shopos/office
sudo ln -s "$GITHUB_WORKSPACE/image/package/usr/share/msfixit-shopos/office" /usr/share/msfixit-shopos/office
sudo mkdir -p \
  /data/office/documents/invoices \
  /data/office/documents/credit-notes \
  /data/office/documents/delivery-notes \
  /data/office/documents/reminders \
  /data/office/documents/customs \
  /data/office/labels \
  /data/office/exports/prosaldo \
  /data/office/archive

cat > /tmp/order.json <<'EOF_ORDER'
{
  "source_system": "woocommerce",
  "source_order_id": "1001",
  "source_order_number": "1001",
  "source_document_id": "1001",
  "order_status": "processing",
  "customer_type": "consumer",
  "currency": "EUR",
  "issue_date": "2026-07-01",
  "service_date": "2026-07-01",
  "tax_mode": "at_small_business_exempt",
  "billing": {
    "first_name": "Erika",
    "last_name": "Mustermann",
    "address_1": "Musterweg 2",
    "postcode": "5020",
    "city": "Salzburg",
    "country": "AT",
    "email": "erika@example.invalid"
  },
  "shipping": {
    "first_name": "Erika",
    "last_name": "Mustermann",
    "address_1": "Musterweg 2",
    "postcode": "5020",
    "city": "Salzburg",
    "country": "AT"
  },
  "totals": {"net": 119.90, "tax": 0, "gross": 119.90},
  "lines": [{
    "article_number": "MF-00000001",
    "description": "CI Test Product",
    "quantity": 1,
    "unit": "Stk",
    "unit_net": 119.90,
    "tax_rate": 0,
    "line_net": 119.90,
    "line_tax": 0,
    "line_gross": 119.90,
    "metadata": {"hs_code": "84718000", "origin_country": "DE"}
  }]
}
EOF_ORDER

office=(sudo php image/package/usr/local/sbin/msfixit-office)

echo '### Create invoice draft'
invoice_json="$("${office[@]}" document-create invoice /tmp/order.json)"
echo "$invoice_json" | jq .
invoice_id="$(jq -r '.id' <<< "$invoice_json")"
test -n "$invoice_id"

echo '### Finalize invoice and render PDF'
finalized_json="$("${office[@]}" document-finalize "$invoice_id")"
echo "$finalized_json" | jq .
invoice_number="$(jq -r '.document_number' <<< "$finalized_json")"
invoice_pdf="$(jq -r '.pdf_path' <<< "$finalized_json")"
test "$invoice_number" = RE-2026-000001
test -s "$invoice_pdf"
sha256sum "$invoice_pdf"

echo '### Verify immutable final document'
if "${office_db[@]}" --execute="UPDATE office_documents SET gross_total=1 WHERE id='${invoice_id}'"; then
  echo 'Final invoice immutability trigger did not block an update.' >&2
  exit 1
fi
if "${office_db[@]}" --execute="DELETE FROM office_documents WHERE id='${invoice_id}'"; then
  echo 'Final invoice deletion trigger did not block a delete.' >&2
  exit 1
fi

echo '### Record partial payment'
payment_json="$("${office[@]}" payment-record "$invoice_number" bank BANK-CI-1 20.00 EUR '2026-07-02 10:00:00' "$invoice_number")"
echo "$payment_json" | jq .
jq -e '(.open_amount - 99.9 | fabs) < 0.0001' <<< "$payment_json"

echo '### Create overdue payment reminder'
dry_run="$("${office[@]}" dunning-run --dry-run)"
echo "$dry_run" | jq .
jq -e '.created | length == 1' <<< "$dry_run"
dunning_result="$("${office[@]}" dunning-run)"
echo "$dunning_result" | jq .
jq -e '.created | length == 1' <<< "$dunning_result"
reminder_pdf="$("${office_db[@]}" -Nse "SELECT pdf_path FROM office_reminders WHERE document_id='${invoice_id}' AND reminder_level=0")"
test -s "$reminder_pdf"
sha256sum "$reminder_pdf"

echo '### Build ProSaldo handoff'
export_json="$("${office[@]}" prosaldo-export 2026-07-01 2026-07-31)"
echo "$export_json" | jq .
export_path="$(jq -r '.export_path' <<< "$export_json")"
test -s "$export_path"
unzip -l "$export_path" | tee /tmp/prosaldo-files.txt
grep -q 'documents.csv' /tmp/prosaldo-files.txt
grep -q 'manifest.json' /tmp/prosaldo-files.txt
grep -q 'pdf/RE-2026-000001.pdf' /tmp/prosaldo-files.txt

cat > /tmp/shipment.json <<'EOF_SHIPMENT'
{
  "source_system": "woocommerce",
  "source_order_id": "1001",
  "source_order_number": "1001",
  "order_status": "processing",
  "customer_type": "consumer",
  "currency": "EUR",
  "billing": {"first_name":"Erika","last_name":"Mustermann","country":"AT"},
  "shipping": {
    "first_name": "Erika",
    "last_name": "Mustermann",
    "address_1": "Musterweg 2",
    "postcode": "5020",
    "city": "Salzburg",
    "country": "AT"
  },
  "totals": {"net":119.90,"tax":0,"gross":119.90},
  "carrier_code": "post_at",
  "carrier_product": "test",
  "ship_date": "2026-07-02",
  "packages": [{
    "weight_kg": 1.25,
    "length_cm": 30,
    "width_cm": 20,
    "height_cm": 10,
    "contents_description": "CI Test Product",
    "value_amount": 119.90,
    "value_currency": "EUR"
  }]
}
EOF_SHIPMENT

echo '### Create shipment and archive label'
shipment_json="$("${office[@]}" shipment-create /tmp/shipment.json)"
echo "$shipment_json" | jq .
shipment_id="$(jq -r '.id' <<< "$shipment_json")"
shipment_number="$(jq -r '.shipment_number' <<< "$shipment_json")"
test "$shipment_number" = VS-2026-000001
label_json="$("${office[@]}" label-import "$shipment_id" "$invoice_pdf" TRACK-CI-1)"
echo "$label_json" | jq .
label_path="$(jq -r '.path' <<< "$label_json")"
test -s "$label_path"

echo '### Verify registry and health status'
"${office[@]}" carrier-list | tee /tmp/carriers.json | jq -e '.[] | select(.carrier_code == "post_at" and .enabled == 0)'
"${office[@]}" status | tee /tmp/office-status.json | jq -e '.state == "configured"'

trigger_count="$("${office_db[@]}" --batch --skip-column-names \
  --execute="SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='shopos_office'")"
test "$trigger_count" -ge 5

echo 'Office and fulfillment integration test passed.'
