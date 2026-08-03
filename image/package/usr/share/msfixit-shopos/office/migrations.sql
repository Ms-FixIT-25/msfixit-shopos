INSERT IGNORE INTO office_schema_versions (version_number) VALUES (2);
SET @office_v2_applied := ROW_COUNT();

UPDATE office_reminder_rules
   SET enabled = 0
 WHERE reminder_level >= 1
   AND @office_v2_applied = 1;

SET @has_period_unique := (
    SELECT COUNT(*)
      FROM information_schema.STATISTICS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'office_prosaldo_exports'
       AND INDEX_NAME = 'uq_office_prosaldo_export_period'
);

SET @drop_period_unique_sql := IF(
    @has_period_unique > 0,
    'ALTER TABLE office_prosaldo_exports DROP INDEX uq_office_prosaldo_export_period',
    'SELECT 1'
);
PREPARE office_drop_period_unique FROM @drop_period_unique_sql;
EXECUTE office_drop_period_unique;
DEALLOCATE PREPARE office_drop_period_unique;

SET @has_period_index := (
    SELECT COUNT(*)
      FROM information_schema.STATISTICS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'office_prosaldo_exports'
       AND INDEX_NAME = 'ix_office_prosaldo_export_period'
);

SET @add_period_index_sql := IF(
    @has_period_index = 0,
    'ALTER TABLE office_prosaldo_exports ADD KEY ix_office_prosaldo_export_period (export_period_start, export_period_end)',
    'SELECT 1'
);
PREPARE office_add_period_index FROM @add_period_index_sql;
EXECUTE office_add_period_index;
DEALLOCATE PREPARE office_add_period_index;
