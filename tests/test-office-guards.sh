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

trigger_count="$("${db[@]}" -Nse "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='shopos_office'")"
test "$trigger_count" -ge 11

echo 'Office document and payment guard test passed.'
