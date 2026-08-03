#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"

db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_office)
"${db[@]}" < image/package/usr/share/msfixit-shopos/compliance/tax-decision-migrations.sql
"${db[@]}" < image/package/usr/share/msfixit-shopos/compliance/renderer-guards.sql

office=(sudo env OFFICE_ENV_PATH=/etc/msfixit-shopos/office.env php image/package/usr/local/sbin/msfixit-office)
tax=(sudo env OFFICE_ENV_PATH=/etc/msfixit-shopos/office.env php image/package/usr/local/sbin/msfixit-tax-decision)

cat >> /etc/msfixit-shopos/business.env <<'EOF_CASE_TAX'
TAX_MODE_AT_B2C=at_small_business_exempt
TAX_MODE_AT_B2B=at_small_business_exempt
TAX_MODE_DE_B2C=eu_oss
TAX_MODE_DE_B2B=intra_community_supply
TAX_MODE_CH_B2C=export_third_country
TAX_MODE_CH_B2B=export_third_country
EOF_CASE_TAX

echo '### Advanced and structured renderers start disabled and cannot be self-enabled'
"${db[@]}" -Nse "SELECT CONCAT(capability_code,':',enabled) FROM compliance_capabilities ORDER BY capability_code" | tee /tmp/capabilities.txt
grep -q 'advanced_b2b_tax_invoice_renderer:0' /tmp/capabilities.txt
grep -q 'structured_en16931_invoice_renderer:0' /tmp/capabilities.txt
if "${db[@]}" --execute="UPDATE compliance_capabilities SET enabled=1 WHERE capability_code='advanced_b2b_tax_invoice_renderer'"; then
  echo 'Advanced renderer capability was enabled without verified evidence.' >&2
  exit 1
fi

echo '### Case-aware assistant blocks intra-Community B2B while renderer is incomplete'
cat > /tmp/renderer-b2b-order.json <<'EOF_B2B_ORDER'
{
  "source_system":"woocommerce",
  "source_order_id":"RENDERER-B2B-1",
  "source_order_number":"RENDERER-B2B-1",
  "source_document_id":"RENDERER-B2B-1",
  "order_status":"processing",
  "customer_type":"business",
  "currency":"EUR",
  "issue_date":"2026-08-03",
  "service_date":"2026-08-03",
  "tax_mode":"intra_community_supply",
  "billing":{"company":"German Buyer GmbH","address_1":"Kundenstraße 1","postcode":"10115","city":"Berlin","country":"DE","email":"buyer@example.invalid"},
  "shipping":{"company":"German Buyer GmbH","address_1":"Kundenstraße 1","postcode":"10115","city":"Berlin","country":"DE"},
  "totals":{"net":100,"tax":0,"gross":100},
  "lines":[{"article_number":"MF-STRICT-DE-1","description":"Cross-border B2B device","quantity":1,"unit":"Stk","unit_net":100,"tax_rate":0,"line_net":100,"line_tax":0,"line_gross":100}]
}
EOF_B2B_ORDER
b2b_draft="$("${office[@]}" document-create invoice /tmp/renderer-b2b-order.json)"
b2b_id="$(jq -r '.id' <<< "$b2b_draft")"
cat > /tmp/renderer-b2b-tax.json <<EOF_B2B_TAX
{
  "document_id":"${b2b_id}",
  "destination_country":"DE",
  "customer_type":"business",
  "transaction_type":"goods",
  "customer_vat_id":"DE123456789",
  "vat_id_validation_status":"valid",
  "tax_rate":0,
  "reviewed_by":"CI Tax Review"
}
EOF_B2B_TAX
b2b_decision="$("${tax[@]}" decide /tmp/renderer-b2b-tax.json)"
jq -e '.decision_status == "blocked" and (.decision_reason | contains("advanced DACH tax invoice renderer"))' <<< "$b2b_decision"

# Simulate a faulty adapter bypassing the assistant. MariaDB must still stop
# rendering before number allocation.
forced_decision_id="$(cat /proc/sys/kernel/random/uuid)"
"${db[@]}" --execute="INSERT INTO compliance_tax_decisions(id,document_id,source_system,source_order_id,seller_establishment_country,destination_country,customer_type,customer_vat_id,vat_id_validation_status,tax_scheme,tax_rate,structured_invoice_requirement,decision_status,is_current,decision_reason,decided_at,decided_by) VALUES('${forced_decision_id}','${b2b_id}','woocommerce','RENDERER-B2B-1','AT','DE','business','DE123456789','valid','intra_community_supply',0,'not_required','approved',1,'Forced CI bypass must be stopped by renderer guard',CURRENT_TIMESTAMP,'CI Fault Injection')"
sequence_before="$("${db[@]}" -Nse "SELECT COALESCE((SELECT next_value FROM office_sequences WHERE sequence_name='invoice' AND sequence_year=2026),1)")"
if "${office[@]}" document-finalize "$b2b_id"; then
  echo 'Unsupported intra-Community invoice was rendered.' >&2
  exit 1
fi
sequence_after="$("${db[@]}" -Nse "SELECT COALESCE((SELECT next_value FROM office_sequences WHERE sequence_name='invoice' AND sequence_year=2026),1)")"
test "$sequence_after" = "$sequence_before"
b2b_state="$("${db[@]}" -Nse "SELECT CONCAT(document_status,':',COALESCE(document_number,'NULL'),':',COALESCE(pdf_path,'NULL')) FROM office_documents WHERE id='${b2b_id}'")"
test "$b2b_state" = 'draft:NULL:NULL'

echo '### German B2C OSS invoice is supported and receives German retention period'
cat > /tmp/renderer-b2c-order.json <<'EOF_B2C_ORDER'
{
  "source_system":"woocommerce",
  "source_order_id":"RENDERER-B2C-1",
  "source_order_number":"RENDERER-B2C-1",
  "source_document_id":"RENDERER-B2C-1",
  "order_status":"processing",
  "customer_type":"consumer",
  "currency":"EUR",
  "issue_date":"2026-08-03",
  "service_date":"2026-08-03",
  "tax_mode":"review_required",
  "billing":{"first_name":"Erika","last_name":"Musterfrau","address_1":"Kundenstraße 2","postcode":"10115","city":"Berlin","country":"DE","email":"erika@example.invalid"},
  "shipping":{"first_name":"Erika","last_name":"Musterfrau","address_1":"Kundenstraße 2","postcode":"10115","city":"Berlin","country":"DE"},
  "totals":{"net":100,"tax":19,"gross":119},
  "lines":[{"article_number":"MF-STRICT-DE-1","description":"German consumer device","quantity":1,"unit":"Stk","unit_net":100,"tax_rate":19,"line_net":100,"line_tax":19,"line_gross":119}]
}
EOF_B2C_ORDER
b2c_draft="$("${office[@]}" document-create invoice /tmp/renderer-b2c-order.json)"
b2c_id="$(jq -r '.id' <<< "$b2c_draft")"
cat > /tmp/renderer-b2c-tax.json <<EOF_B2C_TAX
{
  "document_id":"${b2c_id}",
  "destination_country":"DE",
  "customer_type":"consumer",
  "transaction_type":"goods",
  "tax_rate":19,
  "reviewed_by":"CI Tax Review"
}
EOF_B2C_TAX
b2c_decision="$("${tax[@]}" decide /tmp/renderer-b2c-tax.json)"
jq -e '.decision_status == "approved" and .is_current == 1 and .tax_scheme == "eu_oss"' <<< "$b2c_decision"
b2c_final="$("${office[@]}" document-finalize "$b2c_id")"
jq -e '.document_status == "final" and .tax_mode == "eu_oss"' <<< "$b2c_final"
b2c_retention="$("${db[@]}" -Nse "SELECT CONCAT(jurisdiction_country,':',retention_until) FROM compliance_document_archive WHERE document_id='${b2c_id}'")"
test "$b2c_retention" = 'DE:2034-12-31'

echo '### Draft tax decision is superseded, not overwritten'
cat > /tmp/versioned-order.json <<'EOF_VERSIONED_ORDER'
{
  "source_system":"woocommerce",
  "source_order_id":"TAX-VERSION-1",
  "source_order_number":"TAX-VERSION-1",
  "source_document_id":"TAX-VERSION-1",
  "order_status":"processing",
  "customer_type":"consumer",
  "currency":"EUR",
  "issue_date":"2026-08-03",
  "service_date":"2026-08-03",
  "tax_mode":"review_required",
  "billing":{"first_name":"Version","last_name":"Test","address_1":"Kundenstraße 3","postcode":"10115","city":"Berlin","country":"DE","email":"version@example.invalid"},
  "shipping":{"first_name":"Version","last_name":"Test","address_1":"Kundenstraße 3","postcode":"10115","city":"Berlin","country":"DE"},
  "totals":{"net":50,"tax":9.5,"gross":59.5},
  "lines":[{"article_number":"MF-STRICT-DE-1","description":"Versioned tax device","quantity":1,"unit":"Stk","unit_net":50,"tax_rate":19,"line_net":50,"line_tax":9.5,"line_gross":59.5}]
}
EOF_VERSIONED_ORDER
version_draft="$("${office[@]}" document-create invoice /tmp/versioned-order.json)"
version_id="$(jq -r '.id' <<< "$version_draft")"
cat > /tmp/version-tax-1.json <<EOF_VERSION_TAX_1
{"document_id":"${version_id}","destination_country":"DE","customer_type":"consumer","transaction_type":"goods","tax_rate":19,"reviewed_by":"CI Tax Review"}
EOF_VERSION_TAX_1
first_decision="$("${tax[@]}" decide /tmp/version-tax-1.json)"
first_id="$(jq -r '.id' <<< "$first_decision")"
cat > /tmp/version-tax-2.json <<EOF_VERSION_TAX_2
{
  "document_id":"${version_id}",
  "destination_country":"DE",
  "customer_type":"consumer",
  "transaction_type":"goods",
  "tax_scheme":"destination_vat_de",
  "tax_rate":19,
  "reviewed_by":"CI Senior Tax Review",
  "decision_reason":"Manual destination registration test"
}
EOF_VERSION_TAX_2
second_decision="$("${tax[@]}" decide /tmp/version-tax-2.json)"
second_id="$(jq -r '.id' <<< "$second_decision")"
test "$second_id" != "$first_id"
current_count="$("${db[@]}" -Nse "SELECT COUNT(*) FROM compliance_tax_decisions WHERE document_id='${version_id}' AND decision_status='approved' AND is_current=1")"
test "$current_count" = 1
superseded="$("${db[@]}" -Nse "SELECT CONCAT(is_current,':',superseded_by_id IS NOT NULL) FROM compliance_tax_decisions WHERE id='${first_id}'")"
test "$superseded" = '0:1'
"${tax[@]}" show "$version_id" | jq -e --arg id "$second_id" '.id == $id and .tax_scheme == "destination_vat_de"'
"${tax[@]}" history "$version_id" | jq -e 'length == 2'

echo '### Swiss decision remains blocked until Incoterm and customs pricing are reviewed'
cat > /tmp/ch-order.json <<'EOF_CH_ORDER'
{
  "source_system":"woocommerce","source_order_id":"CH-BLOCK-1","source_order_number":"CH-BLOCK-1","source_document_id":"CH-BLOCK-1",
  "order_status":"processing","customer_type":"consumer","currency":"CHF","issue_date":"2026-08-03","service_date":"2026-08-03","tax_mode":"review_required",
  "billing":{"first_name":"Helvetia","last_name":"Test","address_1":"Testweg 1","postcode":"8001","city":"Zürich","country":"CH","email":"ch@example.invalid"},
  "shipping":{"first_name":"Helvetia","last_name":"Test","address_1":"Testweg 1","postcode":"8001","city":"Zürich","country":"CH"},
  "totals":{"net":100,"tax":0,"gross":100},
  "lines":[{"article_number":"MF-STRICT-DE-1","description":"Swiss export test","quantity":1,"unit":"Stk","unit_net":100,"tax_rate":0,"line_net":100,"line_tax":0,"line_gross":100}]
}
EOF_CH_ORDER
ch_draft="$("${office[@]}" document-create invoice /tmp/ch-order.json)"
ch_id="$(jq -r '.id' <<< "$ch_draft")"
cat > /tmp/ch-tax.json <<EOF_CH_TAX
{"document_id":"${ch_id}","destination_country":"CH","customer_type":"consumer","transaction_type":"goods","tax_rate":0,"reviewed_by":"CI Tax Review"}
EOF_CH_TAX
"${tax[@]}" decide /tmp/ch-tax.json | jq -e '.decision_status == "blocked" and (.decision_reason | contains("Swiss Incoterm")) and (.decision_reason | contains("customs"))'

echo 'DACH tax assistant, decision versioning and renderer-boundary test passed.'
