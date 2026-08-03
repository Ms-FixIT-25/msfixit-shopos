#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"

db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_office)
office=(sudo env OFFICE_ENV_PATH=/etc/msfixit-shopos/office.env php image/package/usr/local/sbin/msfixit-office)

before="$("${db[@]}" -Nse "SELECT COALESCE((SELECT next_value FROM office_sequences WHERE sequence_name='invoice' AND sequence_year=2026),1)")"

cat > /tmp/numbering-block-order.json <<'EOF_NUMBERING_ORDER'
{
  "source_system":"woocommerce",
  "source_order_id":"NUMBERING-BLOCK-1",
  "source_order_number":"NUMBERING-BLOCK-1",
  "source_document_id":"NUMBERING-BLOCK-1",
  "order_status":"processing",
  "customer_type":"business",
  "currency":"EUR",
  "issue_date":"2026-08-03",
  "service_date":"2026-08-03",
  "tax_mode":"intra_community_supply",
  "billing":{"company":"Blocked Buyer GmbH","address_1":"Rechnungsweg 2","postcode":"5020","city":"Salzburg","country":"AT","email":"blocked@example.invalid"},
  "shipping":{"company":"Blocked Buyer GmbH","address_1":"Lieferstraße 2","postcode":"10115","city":"Berlin","country":"DE"},
  "totals":{"net":50,"tax":0,"gross":50},
  "lines":[{"article_number":"MF-STRICT-DE-1","description":"Blocked compliance invoice","quantity":1,"unit":"Stk","unit_net":50,"tax_rate":0,"line_net":50,"line_tax":0,"line_gross":50}]
}
EOF_NUMBERING_ORDER

draft_json="$("${office[@]}" document-create invoice /tmp/numbering-block-order.json)"
document_id="$(jq -r '.id' <<< "$draft_json")"

if "${office[@]}" document-finalize "$document_id"; then
  echo 'Invoice without tax decision reached rendering.' >&2
  exit 1
fi

after="$("${db[@]}" -Nse "SELECT COALESCE((SELECT next_value FROM office_sequences WHERE sequence_name='invoice' AND sequence_year=2026),1)")"
test "$after" = "$before"

state="$("${db[@]}" -Nse "SELECT CONCAT(document_status,':',COALESCE(document_number,'NULL'),':',COALESCE(pdf_path,'NULL')) FROM office_documents WHERE id='${document_id}'")"
test "$state" = 'draft:NULL:NULL'

echo 'Compliance preflight rolled back invoice number allocation and rendering state.'
