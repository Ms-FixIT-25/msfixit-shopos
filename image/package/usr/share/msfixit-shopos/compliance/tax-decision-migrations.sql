ALTER TABLE compliance_tax_decisions
    ADD COLUMN IF NOT EXISTS is_current TINYINT(1) NOT NULL DEFAULT 1 AFTER decision_status,
    ADD COLUMN IF NOT EXISTS superseded_at TIMESTAMP NULL DEFAULT NULL AFTER decided_by,
    ADD COLUMN IF NOT EXISTS superseded_by_id CHAR(36) NULL AFTER superseded_at;

SET @has_tax_current_index := (
    SELECT COUNT(*) FROM information_schema.STATISTICS
     WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='compliance_tax_decisions'
       AND INDEX_NAME='ix_compliance_tax_current'
);
SET @add_tax_current_index := IF(
    @has_tax_current_index=0,
    'ALTER TABLE compliance_tax_decisions ADD KEY ix_compliance_tax_current (document_id,decision_status,is_current)',
    'SELECT 1'
);
PREPARE compliance_stmt FROM @add_tax_current_index;
EXECUTE compliance_stmt;
DEALLOCATE PREPARE compliance_stmt;

DROP TRIGGER IF EXISTS trg_compliance_tax_approved_immutable_update;
DROP TRIGGER IF EXISTS trg_compliance_tax_one_current_insert;
DROP TRIGGER IF EXISTS trg_compliance_tax_one_current_update;
DROP TRIGGER IF EXISTS trg_office_documents_compliance_archive;

DELIMITER //

CREATE TRIGGER trg_compliance_tax_approved_immutable_update
BEFORE UPDATE ON compliance_tax_decisions
FOR EACH ROW
BEGIN
    IF OLD.decision_status='approved' THEN
        IF NOT (
            OLD.id <=> NEW.id AND
            OLD.document_id <=> NEW.document_id AND
            OLD.source_system <=> NEW.source_system AND
            OLD.source_order_id <=> NEW.source_order_id AND
            OLD.seller_establishment_country <=> NEW.seller_establishment_country AND
            OLD.destination_country <=> NEW.destination_country AND
            OLD.customer_type <=> NEW.customer_type AND
            OLD.customer_vat_id <=> NEW.customer_vat_id AND
            OLD.vat_id_validation_status <=> NEW.vat_id_validation_status AND
            OLD.tax_scheme <=> NEW.tax_scheme AND
            OLD.tax_rate <=> NEW.tax_rate AND
            OLD.structured_invoice_requirement <=> NEW.structured_invoice_requirement AND
            OLD.decision_status <=> NEW.decision_status AND
            OLD.decision_reason <=> NEW.decision_reason AND
            OLD.decided_at <=> NEW.decided_at AND
            OLD.decided_by <=> NEW.decided_by AND
            OLD.created_at <=> NEW.created_at AND
            OLD.is_current=1 AND NEW.is_current=0 AND
            NEW.superseded_at IS NOT NULL AND
            NEW.superseded_by_id IS NOT NULL AND NEW.superseded_by_id<>''
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Approved tax decision is immutable; only an explicit superseding decision may deactivate it';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_compliance_tax_one_current_insert
BEFORE INSERT ON compliance_tax_decisions
FOR EACH ROW
BEGIN
    IF NEW.decision_status='approved' AND NEW.is_current=1 AND EXISTS (
        SELECT 1 FROM compliance_tax_decisions d
         WHERE d.decision_status='approved' AND d.is_current=1
           AND (
                (NEW.document_id IS NOT NULL AND d.document_id=NEW.document_id) OR
                (NEW.document_id IS NULL AND d.document_id IS NULL
                 AND d.source_system=NEW.source_system AND d.source_order_id=NEW.source_order_id)
           )
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Only one current approved tax decision is allowed for a document or source order';
    END IF;
END//

CREATE TRIGGER trg_compliance_tax_one_current_update
BEFORE UPDATE ON compliance_tax_decisions
FOR EACH ROW
BEGIN
    IF NEW.decision_status='approved' AND NEW.is_current=1 AND OLD.is_current<>1 AND EXISTS (
        SELECT 1 FROM compliance_tax_decisions d
         WHERE d.id<>NEW.id AND d.decision_status='approved' AND d.is_current=1
           AND (
                (NEW.document_id IS NOT NULL AND d.document_id=NEW.document_id) OR
                (NEW.document_id IS NULL AND d.document_id IS NULL
                 AND d.source_system=NEW.source_system AND d.source_order_id=NEW.source_order_id)
           )
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Only one current approved tax decision is allowed for a document or source order';
    END IF;
END//

CREATE TRIGGER trg_office_documents_compliance_archive
AFTER UPDATE ON office_documents
FOR EACH ROW
BEGIN
    DECLARE jurisdiction CHAR(2) DEFAULT 'AT';
    DECLARE retention_years INT DEFAULT 7;
    DECLARE retention_date DATE;

    IF OLD.document_status<>'final' AND NEW.document_status='final' AND
       NEW.pdf_sha256 IS NOT NULL AND NEW.document_number IS NOT NULL
    THEN
        SELECT COALESCE(MAX(destination_country),'AT') INTO jurisdiction
          FROM compliance_tax_decisions
         WHERE document_id=NEW.id AND decision_status='approved' AND is_current=1;
        SELECT COALESCE(MAX(accounting_retention_years),7) INTO retention_years
          FROM compliance_market_profiles
         WHERE country_code IN ('AT',jurisdiction);
        SET retention_date=STR_TO_DATE(CONCAT(YEAR(NEW.issue_date)+retention_years,'-12-31'),'%Y-%m-%d');
        INSERT IGNORE INTO compliance_document_archive
        (document_id,jurisdiction_country,document_type,document_number,document_sha256,retention_until)
        VALUES
        (NEW.id,jurisdiction,NEW.document_type,NEW.document_number,NEW.pdf_sha256,retention_date);
    END IF;
END//

DELIMITER ;
