#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"

db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_office)

invoice_id="$("${db[@]}" -Nse "SELECT id FROM office_documents WHERE document_number='RE-2026-000001'")"
payment_id="$("${db[@]}" -Nse "SELECT id FROM office_payments WHERE external_payment_id='BANK-CI-1'")"

test -n "$invoice_id"
test -n "$payment_id"

if "${db[@]}" --execute="UPDATE office_documents SET document_status='draft' WHERE id='${invoice_id}'"; then
  echo 'Final invoice could be unlocked through a status change.' >&2
  exit 1
fi

if "${db[@]}" --execute="INSERT INTO office_document_lines (document_id,line_number,description,quantity,unit) VALUES ('${invoice_id}',99,'Injected line',1,'Stk')"; then
  echo 'A line could be inserted into a final invoice.' >&2
  exit 1
fi

if "${db[@]}" --execute="UPDATE office_payment_allocations SET allocated_amount=30 WHERE payment_id='${payment_id}' AND document_id='${invoice_id}'"; then
  echo 'A recorded payment allocation could be changed.' >&2
  exit 1
fi

if "${db[@]}" --execute="DELETE FROM office_payments WHERE id='${payment_id}'"; then
  echo 'A recorded payment could be deleted.' >&2
  exit 1
fi

if "${db[@]}" --execute="UPDATE office_payments SET amount=200 WHERE id='${payment_id}'"; then
  echo 'A recorded payment could be changed.' >&2
  exit 1
fi

invalid_order='00000000-0000-4000-8000-000000000201'
invalid_document='00000000-0000-4000-8000-000000000202'
"${db[@]}" --execute="
  INSERT INTO office_orders
    (id,source_system,source_order_id,order_status,billing_json,shipping_json,totals_json)
  VALUES
    ('${invalid_order}','ci','invalid-tax','test','{}','{}','{\"net\":100,\"tax\":20,\"gross\":120}');
  INSERT INTO office_documents
    (id,order_id,document_type,document_status,language_code,currency,tax_mode,
     issue_date,due_date,customer_type,customer_name,billing_json,shipping_json,
     net_total,tax_total,gross_total,source_system,source_document_id,snapshot_json)
  VALUES
    ('${invalid_document}','${invalid_order}','invoice','draft','de_AT','EUR','at_small_business_exempt',
     '2026-07-01','2026-07-15','consumer','Invalid Tax Test','{}','{}',
     100,20,120,'ci','invalid-tax','{}');
  INSERT INTO office_document_lines
    (document_id,line_number,description,quantity,unit,unit_net,tax_rate,line_net,line_tax,line_gross)
  VALUES
    ('${invalid_document}',1,'Invalid taxed exempt line',1,'Stk',100,20,100,20,120);
"

if "${db[@]}" --execute="
  UPDATE office_documents
     SET document_number='RE-2026-999999',
         document_status='final',
         pdf_path='/tmp/invalid.pdf',
         pdf_sha256=REPEAT('a',64),
         finalized_at=CURRENT_TIMESTAMP
   WHERE id='${invalid_document}'"; then
  echo 'A tax-exempt invoice containing charged tax could be finalized.' >&2
  exit 1
fi

trigger_count="$("${db[@]}" -Nse "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='shopos_office'")"
test "$trigger_count" -ge 12

echo 'Office document and payment guard test passed.'
