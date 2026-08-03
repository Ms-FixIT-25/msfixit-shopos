SET @has_tax_source_unique := (
    SELECT COUNT(*) FROM information_schema.STATISTICS
     WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='compliance_tax_decisions'
       AND INDEX_NAME='uq_compliance_tax_source'
);
SET @drop_tax_source_unique := IF(
    @has_tax_source_unique > 0,
    'ALTER TABLE compliance_tax_decisions DROP INDEX uq_compliance_tax_source',
    'SELECT 1'
);
PREPARE compliance_stmt FROM @drop_tax_source_unique;
EXECUTE compliance_stmt;
DEALLOCATE PREPARE compliance_stmt;

SET @has_tax_source_index := (
    SELECT COUNT(*) FROM information_schema.STATISTICS
     WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='compliance_tax_decisions'
       AND INDEX_NAME='ix_compliance_tax_source'
);
SET @add_tax_source_index := IF(
    @has_tax_source_index = 0,
    'ALTER TABLE compliance_tax_decisions ADD KEY ix_compliance_tax_source (source_system, source_order_id)',
    'SELECT 1'
);
PREPARE compliance_stmt FROM @add_tax_source_index;
EXECUTE compliance_stmt;
DEALLOCATE PREPARE compliance_stmt;

DROP TRIGGER IF EXISTS trg_compliance_legal_evidence_insert;
DROP TRIGGER IF EXISTS trg_compliance_legal_evidence_update;
DROP TRIGGER IF EXISTS trg_compliance_registration_evidence_insert;
DROP TRIGGER IF EXISTS trg_compliance_registration_evidence_update;
DROP TRIGGER IF EXISTS trg_compliance_supplier_evidence_insert;
DROP TRIGGER IF EXISTS trg_compliance_supplier_evidence_update;
DROP TRIGGER IF EXISTS trg_compliance_product_evidence_insert;
DROP TRIGGER IF EXISTS trg_compliance_product_evidence_update;
DROP TRIGGER IF EXISTS trg_compliance_tax_case_insert;
DROP TRIGGER IF EXISTS trg_compliance_tax_case_update;
DROP TRIGGER IF EXISTS trg_compliance_market_approval_guard;
DROP TRIGGER IF EXISTS trg_office_documents_compliance_before_final;
DROP TRIGGER IF EXISTS trg_office_documents_compliance_archive;

DELIMITER //

CREATE TRIGGER trg_compliance_legal_evidence_insert
BEFORE INSERT ON compliance_legal_documents
FOR EACH ROW
BEGIN
    DECLARE durable_required INT DEFAULT 0;
    SELECT COALESCE(MAX(must_be_durable_medium),0) INTO durable_required
      FROM compliance_market_required_documents
     WHERE country_code=NEW.country_code AND document_type=NEW.document_type;

    IF NEW.approval_status='approved' THEN
        IF NEW.approved_by IS NULL OR NEW.approved_by='' OR
           NEW.content_sha256 NOT REGEXP '^[0-9a-f]{64}$'
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Approved legal documents require actor and content SHA-256';
        END IF;
        IF durable_required=1 AND
           (NEW.file_path IS NULL OR NEW.file_path='' OR
            NEW.file_sha256 IS NULL OR NEW.file_sha256 NOT REGEXP '^[0-9a-f]{64}$')
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Durable-medium legal document requires an archived hashed file';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_compliance_legal_evidence_update
BEFORE UPDATE ON compliance_legal_documents
FOR EACH ROW
BEGIN
    DECLARE durable_required INT DEFAULT 0;
    SELECT COALESCE(MAX(must_be_durable_medium),0) INTO durable_required
      FROM compliance_market_required_documents
     WHERE country_code=NEW.country_code AND document_type=NEW.document_type;

    IF NEW.approval_status='approved' THEN
        IF NEW.approved_by IS NULL OR NEW.approved_by='' OR
           NEW.content_sha256 NOT REGEXP '^[0-9a-f]{64}$'
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Approved legal documents require actor and content SHA-256';
        END IF;
        IF durable_required=1 AND
           (NEW.file_path IS NULL OR NEW.file_path='' OR
            NEW.file_sha256 IS NULL OR NEW.file_sha256 NOT REGEXP '^[0-9a-f]{64}$')
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Durable-medium legal document requires an archived hashed file';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_compliance_registration_evidence_insert
BEFORE INSERT ON compliance_business_registrations
FOR EACH ROW
BEGIN
    IF NEW.registration_status='verified' AND
       (NEW.verified_by IS NULL OR NEW.verified_by='' OR
        NEW.verification_source IS NULL OR NEW.verification_source='' OR
        NEW.evidence_path IS NULL OR NEW.evidence_path='' OR
        NEW.evidence_sha256 IS NULL OR NEW.evidence_sha256 NOT REGEXP '^[0-9a-f]{64}$')
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Verified registration requires actor, source and hashed evidence';
    END IF;
END//

CREATE TRIGGER trg_compliance_registration_evidence_update
BEFORE UPDATE ON compliance_business_registrations
FOR EACH ROW
BEGIN
    IF NEW.registration_status='verified' AND
       (NEW.verified_by IS NULL OR NEW.verified_by='' OR
        NEW.verification_source IS NULL OR NEW.verification_source='' OR
        NEW.evidence_path IS NULL OR NEW.evidence_path='' OR
        NEW.evidence_sha256 IS NULL OR NEW.evidence_sha256 NOT REGEXP '^[0-9a-f]{64}$')
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Verified registration requires actor, source and hashed evidence';
    END IF;
END//

CREATE TRIGGER trg_compliance_supplier_evidence_insert
BEFORE INSERT ON compliance_supplier_markets
FOR EACH ROW
BEGIN
    IF NEW.verification_status='verified' AND
       (NEW.verified_by IS NULL OR NEW.verified_by='' OR
        NEW.evidence_path IS NULL OR NEW.evidence_path='' OR
        NEW.evidence_sha256 IS NULL OR NEW.evidence_sha256 NOT REGEXP '^[0-9a-f]{64}$')
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Verified supplier market requires actor and hashed registry evidence';
    END IF;
END//

CREATE TRIGGER trg_compliance_supplier_evidence_update
BEFORE UPDATE ON compliance_supplier_markets
FOR EACH ROW
BEGIN
    IF NEW.verification_status='verified' AND
       (NEW.verified_by IS NULL OR NEW.verified_by='' OR
        NEW.evidence_path IS NULL OR NEW.evidence_path='' OR
        NEW.evidence_sha256 IS NULL OR NEW.evidence_sha256 NOT REGEXP '^[0-9a-f]{64}$')
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Verified supplier market requires actor and hashed registry evidence';
    END IF;
END//

CREATE TRIGGER trg_compliance_product_evidence_insert
BEFORE INSERT ON compliance_product_markets
FOR EACH ROW
BEGIN
    IF NEW.approval_status='approved' AND
       (NEW.approved_by IS NULL OR NEW.approved_by='' OR
        NEW.evidence_path IS NULL OR NEW.evidence_path='' OR
        NEW.evidence_sha256 IS NULL OR NEW.evidence_sha256 NOT REGEXP '^[0-9a-f]{64}$')
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Approved product market requires actor and hashed evidence';
    END IF;
END//

CREATE TRIGGER trg_compliance_product_evidence_update
BEFORE UPDATE ON compliance_product_markets
FOR EACH ROW
BEGIN
    IF NEW.approval_status='approved' AND
       (NEW.approved_by IS NULL OR NEW.approved_by='' OR
        NEW.evidence_path IS NULL OR NEW.evidence_path='' OR
        NEW.evidence_sha256 IS NULL OR NEW.evidence_sha256 NOT REGEXP '^[0-9a-f]{64}$')
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Approved product market requires actor and hashed evidence';
    END IF;
END//

CREATE TRIGGER trg_compliance_tax_case_insert
BEFORE INSERT ON compliance_tax_decisions
FOR EACH ROW
BEGIN
    IF NEW.decision_status='approved' THEN
        IF NEW.decided_by IS NULL OR NEW.decided_by='' OR NEW.decision_reason='' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Approved tax decision requires actor and reason';
        END IF;
        IF NEW.destination_country='CH' AND NEW.tax_scheme<>'export_third_country' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Swiss supply requires reviewed third-country export scheme';
        END IF;
        IF NEW.destination_country='DE' AND NEW.customer_type='business' THEN
            IF NEW.tax_scheme='eu_oss' THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT='OSS is not a B2B tax scheme';
            END IF;
            IF NEW.seller_establishment_country<>'DE' AND NEW.tax_scheme='intra_community_supply' AND
               (NEW.customer_vat_id IS NULL OR NEW.customer_vat_id='' OR NEW.vat_id_validation_status<>'valid')
            THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT='Intra-Community B2B supply requires a valid verified VAT ID';
            END IF;
        END IF;
        IF NEW.destination_country='DE' AND NEW.customer_type<>'business' AND
           NEW.tax_scheme IN ('intra_community_supply','reverse_charge')
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='B2C German sale cannot use B2B intra-Community/reverse-charge scheme';
        END IF;
        IF NEW.structured_invoice_requirement='b2g_structured_required' AND NEW.decision_status='approved' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='B2G decision cannot be approved without a validated structured adapter record';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_compliance_tax_case_update
BEFORE UPDATE ON compliance_tax_decisions
FOR EACH ROW
BEGIN
    IF NEW.decision_status='approved' THEN
        IF NEW.decided_by IS NULL OR NEW.decided_by='' OR NEW.decision_reason='' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Approved tax decision requires actor and reason';
        END IF;
        IF NEW.destination_country='CH' AND NEW.tax_scheme<>'export_third_country' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Swiss supply requires reviewed third-country export scheme';
        END IF;
        IF NEW.destination_country='DE' AND NEW.customer_type='business' AND NEW.tax_scheme='eu_oss' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='OSS is not a B2B tax scheme';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_compliance_market_approval_guard
BEFORE UPDATE ON compliance_market_profiles
FOR EACH ROW
BEGIN
    DECLARE missing_b2c INT DEFAULT 0;
    DECLARE missing_b2b INT DEFAULT 0;
    DECLARE withdrawal_test INT DEFAULT 0;

    IF (NEW.b2c_enabled=1 OR NEW.b2b_enabled=1) AND
       (OLD.b2c_enabled=0 OR OLD.b2b_enabled=0 OR OLD.legal_review_status<>'approved')
    THEN
        SELECT COUNT(*) INTO missing_b2c
          FROM compliance_market_required_documents r
         WHERE r.country_code=NEW.country_code AND r.required_for_b2c=1
           AND NOT EXISTS (
                SELECT 1 FROM compliance_legal_documents d
                 WHERE d.country_code=r.country_code AND d.document_type=r.document_type
                   AND d.active=1 AND d.approval_status='approved'
                   AND d.valid_from<=CURRENT_DATE
                   AND (d.valid_until IS NULL OR d.valid_until>=CURRENT_DATE)
                   AND (r.must_be_durable_medium=0 OR
                        (d.file_path IS NOT NULL AND d.file_path<>'' AND
                         d.file_sha256 REGEXP '^[0-9a-f]{64}$'))
           );
        SELECT COUNT(*) INTO missing_b2b
          FROM compliance_market_required_documents r
         WHERE r.country_code=NEW.country_code AND r.required_for_b2b=1
           AND NOT EXISTS (
                SELECT 1 FROM compliance_legal_documents d
                 WHERE d.country_code=r.country_code AND d.document_type=r.document_type
                   AND d.active=1 AND d.approval_status='approved'
                   AND d.valid_from<=CURRENT_DATE
                   AND (d.valid_until IS NULL OR d.valid_until>=CURRENT_DATE)
                   AND (r.must_be_durable_medium=0 OR
                        (d.file_path IS NOT NULL AND d.file_path<>'' AND
                         d.file_sha256 REGEXP '^[0-9a-f]{64}$'))
           );
        IF (NEW.b2c_enabled=1 AND missing_b2c>0) OR (NEW.b2b_enabled=1 AND missing_b2b>0) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Market cannot be enabled while approved legal evidence is incomplete';
        END IF;
        IF NEW.legal_review_status<>'approved' OR NEW.tax_review_status<>'approved' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Market cannot be enabled before legal and tax review approval';
        END IF;

        IF NEW.b2c_enabled=1 AND
           (NEW.country_code='DE' OR
            (NEW.country_code='AT' AND NEW.withdrawal_function_required_from IS NOT NULL AND CURRENT_DATE>=NEW.withdrawal_function_required_from))
        THEN
            SELECT COUNT(*) INTO withdrawal_test
              FROM compliance_business_registrations
             WHERE country_code=NEW.country_code AND legal_entity_code='seller'
               AND registration_type='WITHDRAWAL_FUNCTION_TEST'
               AND registration_status='verified'
               AND (valid_until IS NULL OR valid_until>=CURRENT_DATE);
            IF withdrawal_test=0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT='B2C market requires a verified electronic withdrawal-function test';
            END IF;
        END IF;
    END IF;
END//

CREATE TRIGGER trg_office_documents_compliance_before_final
BEFORE UPDATE ON office_documents
FOR EACH ROW
BEGIN
    DECLARE approved_decisions INT DEFAULT 0;
    DECLARE decision_country CHAR(2);
    DECLARE decision_scheme VARCHAR(64);
    DECLARE enabled_market INT DEFAULT 0;

    IF OLD.document_status<>'final' AND NEW.document_status='final' AND
       NEW.document_type IN ('invoice','credit_note')
    THEN
        SELECT COUNT(*),MAX(destination_country),MAX(tax_scheme)
          INTO approved_decisions,decision_country,decision_scheme
          FROM compliance_tax_decisions
         WHERE document_id=NEW.id AND decision_status='approved';

        IF approved_decisions<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Final invoice blocked: exactly one approved tax decision is required';
        END IF;
        IF decision_scheme<>NEW.tax_mode THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Final invoice blocked: document tax mode differs from approved tax decision';
        END IF;

        SELECT COUNT(*) INTO enabled_market
          FROM compliance_market_profiles
         WHERE country_code=decision_country
           AND legal_review_status='approved' AND tax_review_status='approved'
           AND ((NEW.customer_type='business' AND b2b_enabled=1) OR
                (NEW.customer_type<>'business' AND b2c_enabled=1));
        IF enabled_market=0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Final invoice blocked: tax destination market is not approved';
        END IF;
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
         WHERE document_id=NEW.id AND decision_status='approved';
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
