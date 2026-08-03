#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"

root=(mariadb --host=127.0.0.1 --port=3306 --user=root)

"${root[@]}" <<'EOF_SQL'
DROP USER IF EXISTS 'shopos_office_wp_ci'@'%';
CREATE USER 'shopos_office_wp_ci'@'%' IDENTIFIED BY 'shopos-ci-wp';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'shopos_office_wp_ci'@'%';
GRANT SELECT ON shopos_office.* TO 'shopos_office_wp_ci'@'%';
GRANT INSERT ON shopos_office.office_outbox TO 'shopos_office_wp_ci'@'%';
FLUSH PRIVILEGES;
EOF_SQL

wp=(mariadb --host=127.0.0.1 --port=3306 --user=shopos_office_wp_ci --password=shopos-ci-wp shopos_office)

"${wp[@]}" -Nse "SELECT COUNT(*) FROM office_documents" >/dev/null

uuid='00000000-0000-4000-8000-000000000099'
"${wp[@]}" --execute="INSERT INTO office_outbox (event_uuid,aggregate_type,aggregate_id,event_type,payload_json) VALUES ('${uuid}','ci','${uuid}','ci.permission.test','{}')"

invoice_id="$("${wp[@]}" -Nse "SELECT id FROM office_documents WHERE document_number='RE-2026-000001'")"
test -n "$invoice_id"

if "${wp[@]}" --execute="UPDATE office_documents SET sent_at=CURRENT_TIMESTAMP WHERE id='${invoice_id}'"; then
  echo 'WordPress Office user could update an invoice.' >&2
  exit 1
fi

if "${wp[@]}" --execute="INSERT INTO office_payments (id,payment_source,external_payment_id,paid_at,amount,currency) VALUES ('00000000-0000-4000-8000-000000000098','ci','unauthorized',CURRENT_TIMESTAMP,1,'EUR')"; then
  echo 'WordPress Office user could insert a payment.' >&2
  exit 1
fi

"${root[@]}" --execute="DROP USER 'shopos_office_wp_ci'@'%'"

echo 'WordPress Office privilege test passed.'
