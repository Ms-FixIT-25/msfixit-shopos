#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"
: "${GITHUB_WORKSPACE:=$(pwd)}"

db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_office)

"${db[@]}" < image/package/usr/share/msfixit-shopos/compliance/schema.sql
"${db[@]}" < image/package/usr/share/msfixit-shopos/compliance/guards.sql

sudo install -d -m 0750 /usr/share/msfixit-shopos/compliance /data/office/compliance/evidence /data/office/compliance/legal-documents
sudo rm -rf /usr/share/msfixit-shopos/compliance
sudo ln -s "$GITHUB_WORKSPACE/image/package/usr/share/msfixit-shopos/compliance" /usr/share/msfixit-shopos/compliance

cat > /tmp/compliance-business.env <<'EOF_BUSINESS'
BUSINESS_CONFIG_APPROVED=yes
BUSINESS_NAME=Ms. FixIT
BUSINESS_LEGAL_NAME=Ms. FixIT CI Test
BUSINESS_OWNER_NAME=CI
BUSINESS_STREET=Teststraße 1
BUSINESS_POSTCODE=5020
BUSINESS_CITY=Salzburg
BUSINESS_COUNTRY=AT
BUSINESS_EMAIL=ci@example.invalid
BUSINESS_IBAN=AT000000000000000000
DEFAULT_TAX_MODE=review_required
TAX_MODE_AT=at_small_business_exempt
TAX_MODE_DE=review_required
TAX_MODE_CH=export_third_country
SMALL_BUSINESS_NOTICE=Umsatzsteuerbefreit aufgrund der Kleinunternehmerregelung.
INVOICE_PREFIX=RE
CREDIT_NOTE_PREFIX=GU
DELIVERY_NOTE_PREFIX=LS
REMINDER_PREFIX=MA
SHIPMENT_PREFIX=VS
INVOICE_PAYMENT_DAYS=14
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
STRUCTURED_EINVOICE_ENABLED=no
B2G_EINVOICE_ENABLED=no
CH_VOLUNTARY_WITHDRAWAL_ENABLED=no
EOF_BUSINESS
sudo install -m 0640 /tmp/compliance-business.env /etc/msfixit-shopos/business.env

compliance=(sudo env OFFICE_ENV_PATH=/etc/msfixit-shopos/office.env php image/package/usr/local/sbin/msfixit-compliance)
office=(sudo env OFFICE_ENV_PATH=/etc/msfixit-shopos/office.env php image/package/usr/local/sbin/msfixit-office)

echo '### Markets start closed and Switzerland has no invented statutory withdrawal right'
"${compliance[@]}" status | tee /tmp/compliance-status.json
jq -e '.markets.AT.b2c_enabled == false and .markets.DE.b2c_enabled == false and .markets.CH.withdrawal_policy == "none_statutory" and .markets.AT.retention_years == 7 and .markets.DE.retention_years == 8 and .markets.CH.retention_years == 10' /tmp/compliance-status.json

if "${compliance[@]}" market-approve AT CI; then
  echo 'AT market was approved without legal documents.' >&2
  exit 1
fi

echo '### Approve versioned Austrian legal documents'
index=0
for type in imprint terms privacy withdrawal shipping payment warranty_returns product_safety; do
  index=$((index+1))
  hash="$(printf 'AT-%s-%02d' "$type" "$index" | sha256sum | awk '{print $1}')"
  cat > "/tmp/legal-${type}.json" <<EOF_LEGAL
{
  "country_code": "AT",
  "document_type": "${type}",
  "version_label": "CI-1",
  "wp_page_slug": "${type}",
  "content_sha256": "${hash}",
  "valid_from": "2026-08-03",
  "approved_by": "CI Legal Review",
  "source_notes": "CI fixture, not production legal advice"
}
EOF_LEGAL
  "${compliance[@]}" legal-approve "/tmp/legal-${type}.json" | jq -e '.active == true'
done

"${compliance[@]}" market-approve AT 'CI Legal and Tax Review' | jq -e '.b2c_enabled == 1 and .b2b_enabled == 1 and .legal_review_status == "approved" and .tax_review_status == "approved"'

echo '### Approved legal text can only be deactivated, never rewritten or deleted'
legal_id="$("${db[@]}" -Nse "SELECT id FROM compliance_legal_documents WHERE country_code='AT' AND document_type='terms' AND active=1")"
if "${db[@]}" --execute="UPDATE compliance_legal_documents SET content_sha256=REPEAT('f',64) WHERE id='${legal_id}'"; then
  echo 'Active approved legal text was mutable.' >&2
  exit 1
fi
if "${db[@]}" --execute="DELETE FROM compliance_legal_documents WHERE id='${legal_id}'"; then
  echo 'Legal text version could be deleted.' >&2
  exit 1
fi

cat > /tmp/at-packaging.json <<'EOF_AT_REG'
{
  "country_code": "AT",
  "legal_entity_code": "seller",
  "registration_type": "PACKAGING_SYSTEM",
  "registration_number": "AT-CI-PACKAGING",
  "holder_name": "Ms. FixIT CI Test",
  "registration_status": "verified",
  "verified_by": "CI Compliance",
  "verification_source": "CI fixture"
}
EOF_AT_REG
"${compliance[@]}" registration-set /tmp/at-packaging.json | jq -e '.status == "verified"'

echo '### GPSR gate rejects a non-EU manufacturer without EU responsible person'
cat > /tmp/product-bad.json <<'EOF_PRODUCT_BAD'
{
  "article_number": "MF-CI-LEGAL-1",
  "country_code": "AT",
  "product_identifier": "MODEL-CI-1",
  "manufacturer_name": "Outside EU Manufacturer",
  "manufacturer_postal_address": "1 Test Road, Shenzhen, CN",
  "manufacturer_email": "manufacturer@example.invalid",
  "manufacturer_outside_eu": true,
  "safety_warnings_de": "Nur bestimmungsgemäß verwenden.",
  "delivery_min_days": 2,
  "delivery_max_days": 5,
  "legal_guarantee_months": 24,
  "approval_status": "approved",
  "approved_by": "CI Product Review"
}
EOF_PRODUCT_BAD
if "${compliance[@]}" product-set /tmp/product-bad.json; then
  echo 'Non-EU product was approved without EU responsible person.' >&2
  exit 1
fi

cat > /tmp/product-good.json <<'EOF_PRODUCT_GOOD'
{
  "article_number": "MF-CI-LEGAL-1",
  "country_code": "AT",
  "product_identifier": "MODEL-CI-1",
  "manufacturer_name": "Outside EU Manufacturer",
  "manufacturer_postal_address": "1 Test Road, Shenzhen, CN",
  "manufacturer_email": "manufacturer@example.invalid",
  "manufacturer_outside_eu": true,
  "eu_responsible_person_name": "EU Responsible GmbH",
  "eu_responsible_person_postal_address": "EU-Straße 1, 5020 Salzburg, AT",
  "eu_responsible_person_email": "responsible@example.invalid",
  "safety_warnings_de": "Nur bestimmungsgemäß verwenden.",
  "instructions_languages": "de",
  "ce_required": true,
  "ce_confirmed": true,
  "electrical_equipment": false,
  "contains_battery": false,
  "delivery_min_days": 2,
  "delivery_max_days": 5,
  "legal_guarantee_months": 24,
  "economic_operator_role": "importer",
  "approval_status": "approved",
  "approved_by": "CI Product Review"
}
EOF_PRODUCT_GOOD
"${compliance[@]}" product-set /tmp/product-good.json | jq -e '.approved == true'
"${compliance[@]}" product-check MF-CI-LEGAL-1 AT | jq -e '.approved == true'

echo '### Final invoice requires approved market and tax decision'
cat > /tmp/compliance-order.json <<'EOF_ORDER'
{
  "source_system": "woocommerce",
  "source_order_id": "COMPLIANCE-1",
  "source_order_number": "COMPLIANCE-1",
  "source_document_id": "COMPLIANCE-1",
  "order_status": "processing",
  "customer_type": "consumer",
  "currency": "EUR",
  "issue_date": "2026-08-03",
  "service_date": "2026-08-03",
  "tax_mode": "at_small_business_exempt",
  "billing": {"first_name":"Erika","last_name":"Mustermann","address_1":"Musterweg 2","postcode":"5020","city":"Salzburg","country":"AT","email":"erika@example.invalid"},
  "shipping": {"first_name":"Erika","last_name":"Mustermann","address_1":"Musterweg 2","postcode":"5020","city":"Salzburg","country":"AT"},
  "totals": {"net":119.90,"tax":0,"gross":119.90},
  "lines": [{"article_number":"MF-CI-LEGAL-1","description":"CI compliant product","quantity":1,"unit":"Stk","unit_net":119.90,"tax_rate":0,"line_net":119.90,"line_tax":0,"line_gross":119.90}]
}
EOF_ORDER
invoice_json="$("${office[@]}" document-create invoice /tmp/compliance-order.json)"
invoice_id="$(jq -r '.id' <<< "$invoice_json")"
if "${office[@]}" document-finalize "$invoice_id"; then
  echo 'Invoice finalized without approved tax decision.' >&2
  exit 1
fi
cat > /tmp/tax-decision.json <<EOF_TAX
{
  "document_id": "${invoice_id}",
  "source_system": "woocommerce",
  "source_order_id": "COMPLIANCE-1",
  "seller_establishment_country": "AT",
  "destination_country": "AT",
  "customer_type": "consumer",
  "tax_rate": 0,
  "decided_by": "CI Tax Review"
}
EOF_TAX
"${compliance[@]}" tax-decide /tmp/tax-decision.json | jq -e '.status == "approved" and .tax_scheme == "at_small_business_exempt"'
final_json="$("${office[@]}" document-finalize "$invoice_id")"
invoice_number="$(jq -r '.document_number' <<< "$final_json")"
test -n "$invoice_number"
retention="$("${db[@]}" -Nse "SELECT retention_until FROM compliance_document_archive WHERE document_id='${invoice_id}'")"
test "$retention" = 2033-12-31

if "${db[@]}" --execute="DELETE FROM compliance_document_archive WHERE document_id='${invoice_id}'"; then
  echo 'Compliance archive record could be deleted.' >&2
  exit 1
fi

echo '### Capture immutable checkout evidence and two-step withdrawal event'
checkout_uuid="$(cat /proc/sys/kernel/random/uuid)"
checkout_payload="$(jq -cn --arg id "$checkout_uuid" '{snapshot:{source_order_id:"CHECKOUT-CI-1",country_code:"AT",customer_type:"consumer",currency:"EUR",gross_total:119.90,shipping_total:0,button_label:"Zahlungspflichtig bestellen",payment_method:"bank",delivery_promise:"2–5 Werktage",legal_documents:[{type:"terms",version:"CI-1",sha256:"abc"}],products:[{article_number:"MF-CI-LEGAL-1",approved:true}],consents:{terms:true},captured_at:"2026-08-03 18:00:00"}}')"
"${db[@]}" --execute="INSERT INTO office_outbox(event_uuid,aggregate_type,aggregate_id,event_type,payload_json) VALUES('${checkout_uuid}','compliance','CHECKOUT-CI-1','compliance.checkout.snapshot','$(sed "s/'/''/g" <<< "$checkout_payload")')"
"${compliance[@]}" worker-run 20 | jq -e '.[] | select(.[1] == "processed")'
checkout_id="$("${db[@]}" -Nse "SELECT id FROM compliance_checkout_snapshots WHERE source_order_id='CHECKOUT-CI-1'")"
test -n "$checkout_id"
if "${db[@]}" --execute="UPDATE compliance_checkout_snapshots SET gross_total=1 WHERE id='${checkout_id}'"; then
  echo 'Checkout legal snapshot was mutable.' >&2
  exit 1
fi

withdraw_uuid="$(cat /proc/sys/kernel/random/uuid)"
withdraw_payload='{"withdrawal":{"source_order_id":"CHECKOUT-CI-1","country_code":"AT","requester_name":"Erika Mustermann","requester_email":"erika@example.invalid","items":"gesamte Bestellung","declaration_text":"Hiermit widerrufe ich den Vertrag.","requested_at":"2026-08-03 18:05:00","confirmation_sent_at":"2026-08-03 18:05:01"}}'
"${db[@]}" --execute="INSERT INTO office_outbox(event_uuid,aggregate_type,aggregate_id,event_type,payload_json) VALUES('${withdraw_uuid}','compliance','CHECKOUT-CI-1','compliance.withdrawal.requested','$(sed "s/'/''/g" <<< "$withdraw_payload")')"
"${compliance[@]}" worker-run 20 | jq -e '.[] | select(.[1] == "processed")'
refund_due="$("${db[@]}" -Nse "SELECT refund_due_at FROM compliance_withdrawals WHERE source_order_id='CHECKOUT-CI-1'")"
test "$refund_due" = '2026-08-17 18:05:00'

echo '### German dropship electrical product requires dispatcher packaging and EEE verification'
cat > /tmp/de-supplier.json <<'EOF_DE_SUPPLIER'
{"supplier_code":"DROP-DE","legal_name":"Drop DE GmbH","country_code":"DE","direct_to_customer":true,"status":"approved","approved_by":"CI Supplier Review"}
EOF_DE_SUPPLIER
"${compliance[@]}" supplier-set /tmp/de-supplier.json | jq -e '.status == "approved"'
cat > /tmp/de-supplier-market.json <<'EOF_DE_MARKET_BAD'
{"supplier_code":"DROP-DE","country_code":"DE","actual_dispatcher_name":"Drop DE GmbH","packaging_registration":"DE-LUCID-CI","packaging_system_participation":"CI Dual System","verification_status":"verified","verified_by":"CI Registry Check"}
EOF_DE_MARKET_BAD
"${compliance[@]}" supplier-market-set /tmp/de-supplier-market.json | jq -e '.status == "verified"'
cat > /tmp/de-product.json <<'EOF_DE_PRODUCT'
{
  "article_number":"MF-CI-DE-EEE","country_code":"DE","supplier_code":"DROP-DE","product_identifier":"EEE-CI-1",
  "manufacturer_name":"EU Device GmbH","manufacturer_postal_address":"Gerätestraße 1, 10115 Berlin, DE","manufacturer_email":"device@example.invalid",
  "safety_warnings_de":"Netzteil nicht öffnen.","instructions_languages":"de","ce_required":true,"ce_confirmed":true,
  "electrical_equipment":true,"contains_battery":false,"delivery_min_days":2,"delivery_max_days":4,"legal_guarantee_months":24,
  "approval_status":"approved","approved_by":"CI Product Review"
}
EOF_DE_PRODUCT
if "${compliance[@]}" product-set /tmp/de-product.json; then
  echo 'German electrical product was approved without EEE registration.' >&2
  exit 1
fi
cat > /tmp/de-supplier-market-good.json <<'EOF_DE_MARKET_GOOD'
{"supplier_code":"DROP-DE","country_code":"DE","actual_dispatcher_name":"Drop DE GmbH","packaging_registration":"DE-LUCID-CI","packaging_system_participation":"CI Dual System","eee_registration":"WEEE-REG-DE-CI","verification_status":"verified","verified_by":"CI Registry Check"}
EOF_DE_MARKET_GOOD
"${compliance[@]}" supplier-market-set /tmp/de-supplier-market-good.json >/dev/null
"${compliance[@]}" product-set /tmp/de-product.json | jq -e '.approved == true'

echo '### Conservative threshold monitor blocks Austrian exemption above tolerance'
sale_uuid="$(cat /proc/sys/kernel/random/uuid)"
sale_payload='{"sale":{"source_order_id":"TURNOVER-CI","destination_country":"AT","customer_type":"consumer","currency":"EUR","gross_total":61000,"item_count":1,"calendar_year":2026}}'
"${db[@]}" --execute="INSERT INTO office_outbox(event_uuid,aggregate_type,aggregate_id,event_type,payload_json) VALUES('${sale_uuid}','compliance','TURNOVER-CI','compliance.sale.completed','$(sed "s/'/''/g" <<< "$sale_payload")')"
"${compliance[@]}" worker-run 20 >/tmp/compliance-worker-sale.json
"${compliance[@]}" threshold-status 2026 | jq -e '.AT_SMALL_BUSINESS.tolerance_exceeded == true'
cat > /tmp/tax-threshold.json <<'EOF_TAX_THRESHOLD'
{"source_system":"woocommerce","source_order_id":"COMPLIANCE-THRESHOLD","seller_establishment_country":"AT","destination_country":"AT","customer_type":"consumer","tax_rate":0,"calendar_year":2026,"decided_by":"CI Tax Review"}
EOF_TAX_THRESHOLD
"${compliance[@]}" tax-decide /tmp/tax-threshold.json | jq -e '.status == "blocked" and (.reasons | index("Austrian small-business tolerance amount exceeded"))'

trigger_count="$("${db[@]}" -Nse "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='shopos_office' AND TRIGGER_NAME LIKE 'trg_compliance_%' OR TRIGGER_NAME LIKE 'trg_office_documents_compliance_%'")"
test "$trigger_count" -ge 10

echo 'DACH compliance integration test passed.'
