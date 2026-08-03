#!/usr/bin/env bash
set -Eeuxo pipefail

: "${MYSQL_PWD:?MYSQL_PWD must be set}"

db=(mariadb --host=127.0.0.1 --port=3306 --user=root shopos_office)

"${db[@]}" < image/package/usr/share/msfixit-shopos/office/migrations.sql

version_two="$("${db[@]}" -Nse "SELECT COUNT(*) FROM office_schema_versions WHERE version_number=2")"
test "$version_two" -eq 1

formal_enabled="$("${db[@]}" -Nse "SELECT COUNT(*) FROM office_reminder_rules WHERE reminder_level>=1 AND enabled=1")"
test "$formal_enabled" -eq 0

old_unique="$("${db[@]}" -Nse "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='shopos_office' AND TABLE_NAME='office_prosaldo_exports' AND INDEX_NAME='uq_office_prosaldo_export_period'")"
new_index="$("${db[@]}" -Nse "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='shopos_office' AND TABLE_NAME='office_prosaldo_exports' AND INDEX_NAME='ix_office_prosaldo_export_period'")"
test "$old_unique" -eq 0
test "$new_index" -ge 1

"${db[@]}" --execute="UPDATE office_reminder_rules SET enabled=1 WHERE customer_type='consumer' AND country_code='AT' AND reminder_level=1"
"${db[@]}" < image/package/usr/share/msfixit-shopos/office/migrations.sql

preserved="$("${db[@]}" -Nse "SELECT enabled FROM office_reminder_rules WHERE customer_type='consumer' AND country_code='AT' AND reminder_level=1")"
test "$preserved" -eq 1

sleep 1
export OFFICE_ENV_PATH=/etc/msfixit-shopos/office.env
second_export="$(php image/package/usr/local/sbin/msfixit-office prosaldo-export 2026-07-01 2026-07-31)"
echo "$second_export" | jq -e '.export_path | length > 0'

export_count="$("${db[@]}" -Nse "SELECT COUNT(*) FROM office_prosaldo_exports WHERE export_period_start='2026-07-01' AND export_period_end='2026-07-31'")"
test "$export_count" -ge 2

echo 'Office migration test passed.'
