#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"
: "${GITHUB_WORKSPACE:=$(pwd)}"

db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_office)
"${db[@]}" < image/package/usr/share/msfixit-shopos/compliance/strict-guards.sql
"${db[@]}" < image/package/usr/share/msfixit-shopos/compliance/strict-migrations.sql

compliance=(sudo env OFFICE_ENV_PATH=/etc/msfixit-shopos/office.env php image/package/usr/local/sbin/msfixit-compliance)
office=(sudo env OFFICE_ENV_PATH=/etc/msfixit-shopos/office.env php image/package/usr/local/sbin/msfixit-office)

sudo install -d -m 0750 /data/office/compliance/evidence /data/office/compliance/legal-documents
printf '%%PDF-1.4\n%% ShopOS CI legal evidence\n' | sudo tee /data/office/compliance/legal-documents/legal-ci.pdf >/dev/null
printf '<registry checked="true">CI</registry>\n' | sudo tee /data/office/compliance/evidence/registry-ci.xml >/dev/null
printf '%%PDF-1.4\n%% ShopOS CI product evidence\n' | sudo tee /data/office/compliance/evidence/product-ci.pdf >/dev/null
sudo chmod 0640 \
  /data/office/compliance/legal-documents/legal-ci.pdf \
  /data/office/compliance/evidence/registry-ci.xml \
  /data/office/compliance/evidence/product-ci.pdf

legal_file=/data/office/compliance/legal-documents/legal-ci.pdf
registry_file=/data/office/compliance/evidence/registry-ci.xml
product_file=/data/office/compliance/evidence/product-ci.pdf

echo '### Runtime evidence helper detects valid and modified evidence'
sudo php -r "define('ABSPATH','/'); function add_action(...\$args){} require '${GITHUB_WORKSPACE}/image/package/usr/share/msfixit-shopos/wordpress/msfixit-compliance-runtime.php'; exit(msfixit_runtime_compliance_file_valid('${legal_file}', hash_file('sha256','${legal_file}')) ? 0 : 1);"
sudo cp "$legal_file" /tmp/legal-ci-copy.pdf
legal_hash="$(sudo sha256sum /tmp/legal-ci-copy.pdf | awk '{print $1}')"
printf 'changed\n' | sudo tee -a /tmp/legal-ci-copy.pdf >/dev/null
if sudo php -r "define('ABSPATH','/'); function add_action(...\$args){} require '${GITHUB_WORKSPACE}/image/package/usr/share/msfixit-shopos/wordpress/msfixit-compliance-runtime.php'; exit(msfixit_runtime_compliance_file_valid('/tmp/legal-ci-copy.pdf','${legal_hash}') ? 0 : 1);"; then
  echo 'Modified legal evidence passed the runtime hash check.' >&2
  exit 1
fi

echo '### Older active legal version can be replaced, but new durable version needs a real file'
terms_hash="$(printf 'AT-terms-strict' | sha256sum | awk '{print $1}')"
cat > /tmp/at-terms-no-file.json <<EOF_AT_TERMS_BAD
{
  "country_code":"AT",
  "document_type":"terms",
  "version_label":"CI-STRICT-BAD",
  "wp_page_slug":"terms",
  "content_sha256":"${terms_hash}",
  "valid_from":"2026-08-03",
  "approved_by":"CI Legal Review"
}
EOF_AT_TERMS_BAD
if "${compliance[@]}" legal-approve /tmp/at-terms-no-file.json; then
  echo 'Durable legal text was approved without an archived file.' >&2
  exit 1
fi

cat > /tmp/at-terms-with-file.json <<EOF_AT_TERMS_GOOD
{
  "country_code":"AT",
  "document_type":"terms",
  "version_label":"CI-STRICT-2",
  "wp_page_slug":"terms",
  "content_sha256":"${terms_hash}",
  "file_path":"${legal_file}",
  "valid_from":"2026-08-03",
  "approved_by":"CI Legal Review",
  "source_notes":"Strict CI evidence fixture"
}
EOF_AT_TERMS_GOOD
"${compliance[@]}" legal-approve /tmp/at-terms-with-file.json | jq -e '.active == true and .version_label == "CI-STRICT-2"'
old_at_terms_active="$("${db[@]}" -Nse "SELECT COUNT(*) FROM compliance_legal_documents WHERE country_code='AT' AND document_type='terms' AND version_label='CI-1' AND active=1")"
test "$old_at_terms_active" = 0

echo '### Verified registrations require source, actor and hashed evidence'
cat > /tmp/de-withdrawal-test-bad.json <<'EOF_WITHDRAWAL_BAD'
{
  "country_code":"DE",
  "legal_entity_code":"seller",
  "registration_type":"WITHDRAWAL_FUNCTION_TEST",
  "registration_number":"DE-WITHDRAWAL-CI",
  "holder_name":"Ms. FixIT CI Test",
  "registration_status":"verified",
  "verified_by":"CI Functional Review",
  "verification_source":"CI browser test"
}
EOF_WITHDRAWAL_BAD
if "${compliance[@]}" registration-set /tmp/de-withdrawal-test-bad.json; then
  echo 'Verified withdrawal-function test was accepted without evidence.' >&2
  exit 1
fi
cat > /tmp/de-withdrawal-test-good.json <<EOF_WITHDRAWAL_GOOD
{
  "country_code":"DE",
  "legal_entity_code":"seller",
  "registration_type":"WITHDRAWAL_FUNCTION_TEST",
  "registration_number":"DE-WITHDRAWAL-CI",
  "holder_name":"Ms. FixIT CI Test",
  "registration_status":"verified",
  "verified_by":"CI Functional Review",
  "verification_source":"CI browser test",
  "evidence_path":"${registry_file}"
}
EOF_WITHDRAWAL_GOOD
"${compliance[@]}" registration-set /tmp/de-withdrawal-test-good.json | jq -e '.status == "verified"'

sudo sed -i 's/^TAX_MODE_DE=.*/TAX_MODE_DE=eu_oss/' /etc/msfixit-shopos/business.env

echo '### Approve all required German legal versions with durable files'
index=0
for type in imprint terms privacy withdrawal shipping payment warranty_returns product_safety; do
  index=$((index+1))
  hash="$(printf 'DE-%s-%02d' "$type" "$index" | sha256sum | awk '{print $1}')"
  durable=false
  case "$type" in
    terms|withdrawal|shipping|payment|warranty_returns) durable=true ;;
  esac
  if [ "$durable" = true ]; then
    file_line="  \"file_path\": \"${legal_file}\"," 
  else
    file_line=""
  fi
  cat > "/tmp/de-legal-${type}.json" <<EOF_DE_LEGAL
{
  "country_code":"DE",
  "document_type":"${type}",
  "version_label":"CI-STRICT-1",
  "wp_page_slug":"${type}",
  "content_sha256":"${hash}",
${file_line}
  "valid_from":"2026-08-03",
  "approved_by":"CI German Legal Review",
  "source_notes":"CI fixture, not production legal advice"
}
EOF_DE_LEGAL
  "${compliance[@]}" legal-approve "/tmp/de-legal-${type}.json" | jq -e '.active == true'
done
"${compliance[@]}" market-approve DE 'CI German Legal and Tax Review' | jq -e '.b2c_enabled == 1 and .b2b_enabled == 1'

echo '### Verified dropship dispatcher and approved product require evidence'
cat > /tmp/strict-supplier.json <<'EOF_STRICT_SUPPLIER'
{
  "supplier_code":"STRICT-DROP-DE",
  "legal_name":"Strict Drop DE GmbH",
  "country_code":"DE",
  "direct_to_customer":true,
  "status":"approved",
  "approved_by":"CI Supplier Review"
}
EOF_STRICT_SUPPLIER
"${compliance[@]}" supplier-set /tmp/strict-supplier.json | jq -e '.status == "approved"'

cat > /tmp/strict-supplier-market-bad.json <<'EOF_STRICT_MARKET_BAD'
{
  "supplier_code":"STRICT-DROP-DE",
  "country_code":"DE",
  "actual_dispatcher_name":"Strict Drop DE GmbH",
  "packaging_registration":"DE-LUCID-STRICT-CI",
  "packaging_system_participation":"CI Dual System",
  "eee_registration":"WEEE-STRICT-CI",
  "verification_status":"verified",
  "verified_by":"CI Registry Review"
}
EOF_STRICT_MARKET_BAD
if "${compliance[@]}" supplier-market-set /tmp/strict-supplier-market-bad.json; then
  echo 'Verified dropship dispatcher was accepted without registry evidence.' >&2
  exit 1
fi
cat > /tmp/strict-supplier-market-good.json <<EOF_STRICT_MARKET_GOOD
{
  "supplier_code":"STRICT-DROP-DE",
  "country_code":"DE",
  "actual_dispatcher_name":"Strict Drop DE GmbH",
  "packaging_registration":"DE-LUCID-STRICT-CI",
  "packaging_system_participation":"CI Dual System",
  "eee_registration":"WEEE-STRICT-CI",
  "verification_status":"verified",
  "verified_by":"CI Registry Review",
  "evidence_path":"${registry_file}"
}
EOF_STRICT_MARKET_GOOD
"${compliance[@]}" supplier-market-set /tmp/strict-supplier-market-good.json | jq -e '.status == "verified"'

cat > /tmp/strict-product-no-evidence.json <<'EOF_STRICT_PRODUCT_BAD'
{
  "article_number":"MF-STRICT-DE-1",
  "country_code":"DE",
  "supplier_code":"STRICT-DROP-DE",
  "product_identifier":"STRICT-EEE-1",
  "manufacturer_name":"EU Device GmbH",
  "manufacturer_postal_address":"Gerätestraße 1, 10115 Berlin, DE",
  "manufacturer_email":"device@example.invalid",
  "safety_warnings_de":"Netzteil nicht öffnen.",
  "instructions_languages":"de",
  "ce_required":true,
  "ce_confirmed":true,
  "electrical_equipment":true,
  "contains_battery":false,
  "delivery_min_days":2,
  "delivery_max_days":4,
  "legal_guarantee_months":24,
  "approval_status":"approved",
  "approved_by":"CI Product Review"
}
EOF_STRICT_PRODUCT_BAD
if "${compliance[@]}" product-set /tmp/strict-product-no-evidence.json; then
  echo 'Product was approved without safety evidence.' >&2
  exit 1
fi
cat > /tmp/strict-product-evidenced.json <<EOF_STRICT_PRODUCT_GOOD
{
  "article_number":"MF-STRICT-DE-1",
  "country_code":"DE",
  "supplier_code":"STRICT-DROP-DE",
  "product_identifier":"STRICT-EEE-1",
  "manufacturer_name":"EU Device GmbH",
  "manufacturer_postal_address":"Gerätestraße 1, 10115 Berlin, DE",
  "manufacturer_email":"device@example.invalid",
  "safety_warnings_de":"Netzteil nicht öffnen.",
  "instructions_languages":"de",
  "ce_required":true,
  "ce_confirmed":true,
  "electrical_equipment":true,
  "contains_battery":false,
  "delivery_min_days":2,
  "delivery_max_days":4,
  "legal_guarantee_months":24,
  "approval_status":"approved",
  "approved_by":"CI Product Review",
  "evidence_path":"${product_file}"
}
EOF_STRICT_PRODUCT_GOOD
"${compliance[@]}" product-set /tmp/strict-product-evidenced.json | jq -e '.approved == true'

echo '### Tax guard rejects OSS for German B2B and unverified intra-Community VAT ID'
bad_tax_id="$(cat /proc/sys/kernel/random/uuid)"
if "${db[@]}" --execute="INSERT INTO compliance_tax_decisions(id,source_system,source_order_id,seller_establishment_country,destination_country,customer_type,tax_scheme,structured_invoice_requirement,decision_status,decision_reason,decided_at,decided_by) VALUES('${bad_tax_id}','ci','STRICT-TAX-OSS','AT','DE','business','eu_oss','not_required','approved','invalid CI case',CURRENT_TIMESTAMP,'CI')"; then
  echo 'OSS was accepted for German B2B sale.' >&2
  exit 1
fi
bad_vat_id="$(cat /proc/sys/kernel/random/uuid)"
if "${db[@]}" --execute="INSERT INTO compliance_tax_decisions(id,source_system,source_order_id,seller_establishment_country,destination_country,customer_type,customer_vat_id,vat_id_validation_status,tax_scheme,structured_invoice_requirement,decision_status,decision_reason,decided_at,decided_by) VALUES('${bad_vat_id}','ci','STRICT-TAX-VAT','AT','DE','business','DE123456789','invalid','intra_community_supply','not_required','approved','invalid CI VAT case',CURRENT_TIMESTAMP,'CI')"; then
  echo 'Intra-Community supply was accepted with invalid VAT ID.' >&2
  exit 1
fi

echo '### Austrian seller to German business uses approved destination decision and eight-year retention'
cat > /tmp/strict-b2b-order.json <<'EOF_STRICT_B2B_ORDER'
{
  "source_system":"woocommerce",
  "source_order_id":"STRICT-B2B-1",
  "source_order_number":"STRICT-B2B-1",
  "source_document_id":"STRICT-B2B-1",
  "order_status":"processing",
  "customer_type":"business",
  "currency":"EUR",
  "issue_date":"2026-08-03",
  "service_date":"2026-08-03",
  "tax_mode":"intra_community_supply",
  "billing":{"company":"German Buyer GmbH","address_1":"Rechnungsweg 1","postcode":"5020","city":"Salzburg","country":"AT","email":"buyer@example.invalid"},
  "shipping":{"company":"German Buyer GmbH","address_1":"Lieferstraße 1","postcode":"10115","city":"Berlin","country":"DE"},
  "totals":{"net":100,"tax":0,"gross":100},
  "lines":[{"article_number":"MF-STRICT-DE-1","description":"Strict compliant device","quantity":1,"unit":"Stk","unit_net":100,"tax_rate":0,"line_net":100,"line_tax":0,"line_gross":100}]
}
EOF_STRICT_B2B_ORDER
strict_invoice_json="$("${office[@]}" document-create invoice /tmp/strict-b2b-order.json)"
strict_invoice_id="$(jq -r '.id' <<< "$strict_invoice_json")"
valid_tax_id="$(cat /proc/sys/kernel/random/uuid)"
"${db[@]}" --execute="INSERT INTO compliance_tax_decisions(id,document_id,source_system,source_order_id,seller_establishment_country,destination_country,customer_type,customer_vat_id,vat_id_validation_status,tax_scheme,tax_rate,structured_invoice_requirement,decision_status,decision_reason,decided_at,decided_by) VALUES('${valid_tax_id}','${strict_invoice_id}','woocommerce','STRICT-B2B-1','AT','DE','business','DE123456789','valid','intra_community_supply',0,'not_required','approved','Verified intra-Community B2B CI case',CURRENT_TIMESTAMP,'CI Tax Review')"
strict_final="$("${office[@]}" document-finalize "$strict_invoice_id")"
jq -e '.document_status == "final" and .tax_mode == "intra_community_supply"' <<< "$strict_final"
strict_retention="$("${db[@]}" -Nse "SELECT CONCAT(jurisdiction_country,':',retention_until) FROM compliance_document_archive WHERE document_id='${strict_invoice_id}'")"
test "$strict_retention" = 'DE:2034-12-31'

echo '### Approved tax decision is immutable and audit log remains append-only'
if "${db[@]}" --execute="UPDATE compliance_tax_decisions SET tax_scheme='eu_oss' WHERE id='${valid_tax_id}'"; then
  echo 'Approved tax decision was mutable.' >&2
  exit 1
fi
audit_id="$("${db[@]}" -Nse "SELECT id FROM compliance_audit_log ORDER BY id DESC LIMIT 1")"
if [ -n "$audit_id" ] && "${db[@]}" --execute="DELETE FROM compliance_audit_log WHERE id='${audit_id}'"; then
  echo 'Compliance audit event could be deleted.' >&2
  exit 1
fi

strict_trigger_count="$("${db[@]}" -Nse "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='shopos_office' AND (TRIGGER_NAME LIKE 'trg_compliance_%' OR TRIGGER_NAME LIKE 'trg_office_documents_compliance_%')")"
test "$strict_trigger_count" -ge 20

echo 'Strict DACH evidence and tax-case integration test passed.'
