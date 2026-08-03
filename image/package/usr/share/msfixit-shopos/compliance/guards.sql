DROP TRIGGER IF EXISTS trg_compliance_legal_approved_immutable_update;
DROP TRIGGER IF EXISTS trg_compliance_market_approval_guard;
DROP TRIGGER IF EXISTS trg_compliance_product_approval_guard_insert;
DROP TRIGGER IF EXISTS trg_compliance_product_approval_guard_update;
DROP TRIGGER IF EXISTS trg_office_documents_compliance_before_final;
DROP TRIGGER IF EXISTS trg_office_documents_compliance_archive;

DELIMITER //

CREATE TRIGGER trg_compliance_legal_approved_immutable_update
BEFORE UPDATE ON compliance_legal_documents
FOR EACH ROW
BEGIN
    IF OLD.approval_status = 'approved' AND OLD.active = 1 THEN
        IF NOT (
            NEW.active = 0 AND
            OLD.id <=> NEW.id AND
            OLD.country_code <=> NEW.country_code AND
            OLD.document_type <=> NEW.document_type AND
            OLD.version_label <=> NEW.version_label AND
            OLD.wp_page_slug <=> NEW.wp_page_slug AND
            OLD.content_sha256 <=> NEW.content_sha256 AND
            OLD.file_path <=> NEW.file_path AND
            OLD.file_sha256 <=> NEW.file_sha256 AND
            OLD.valid_from <=> NEW.valid_from AND
            OLD.valid_until <=> NEW.valid_until AND
            OLD.approval_status <=> NEW.approval_status AND
            OLD.approved_at <=> NEW.approved_at AND
            OLD.approved_by <=> NEW.approved_by AND
            OLD.source_notes <=> NEW.source_notes
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Approved legal text is immutable; only deactivate it and approve a new version';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_compliance_market_approval_guard
BEFORE UPDATE ON compliance_market_profiles
FOR EACH ROW
BEGIN
    DECLARE missing_b2c INT DEFAULT 0;
    DECLARE missing_b2b INT DEFAULT 0;

    IF (NEW.b2c_enabled = 1 OR NEW.b2b_enabled = 1) AND
       (OLD.b2c_enabled = 0 OR OLD.b2b_enabled = 0 OR OLD.legal_review_status <> 'approved')
    THEN
        SELECT COUNT(*) INTO missing_b2c
          FROM compliance_market_required_documents r
         WHERE r.country_code=NEW.country_code AND r.required_for_b2c=1
           AND NOT EXISTS (
                SELECT 1 FROM compliance_legal_documents d
                 WHERE d.country_code=r.country_code AND d.document_type=r.document_type
                   AND d.active=1 AND d.approval_status='approved'
                   AND d.valid_from <= CURRENT_DATE
                   AND (d.valid_until IS NULL OR d.valid_until >= CURRENT_DATE)
           );

        SELECT COUNT(*) INTO missing_b2b
          FROM compliance_market_required_documents r
         WHERE r.country_code=NEW.country_code AND r.required_for_b2b=1
           AND NOT EXISTS (
                SELECT 1 FROM compliance_legal_documents d
                 WHERE d.country_code=r.country_code AND d.document_type=r.document_type
                   AND d.active=1 AND d.approval_status='approved'
                   AND d.valid_from <= CURRENT_DATE
                   AND (d.valid_until IS NULL OR d.valid_until >= CURRENT_DATE)
           );

        IF (NEW.b2c_enabled=1 AND missing_b2c > 0) OR (NEW.b2b_enabled=1 AND missing_b2b > 0) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Market cannot be enabled while required approved legal documents are missing';
        END IF;
        IF NEW.legal_review_status <> 'approved' OR NEW.tax_review_status <> 'approved' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Market cannot be enabled before legal and tax review approval';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_compliance_product_approval_guard_insert
BEFORE INSERT ON compliance_product_markets
FOR EACH ROW
BEGIN
    IF NEW.approval_status='approved' THEN
        IF NEW.product_identifier='' OR NEW.manufacturer_name='' OR
           NEW.manufacturer_postal_address='' OR NEW.manufacturer_email='' OR
           NEW.safety_warnings_de IS NULL OR NEW.safety_warnings_de='' OR
           NEW.delivery_min_days IS NULL OR NEW.delivery_max_days IS NULL OR
           NEW.delivery_max_days < NEW.delivery_min_days
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Approved products require manufacturer, safety and delivery data';
        END IF;
        IF NEW.manufacturer_outside_eu=1 AND NEW.country_code IN ('AT','DE') AND
           (NEW.eu_responsible_person_name IS NULL OR NEW.eu_responsible_person_name='' OR
            NEW.eu_responsible_person_postal_address IS NULL OR NEW.eu_responsible_person_postal_address='' OR
            NEW.eu_responsible_person_email IS NULL OR NEW.eu_responsible_person_email='')
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'EU product offer requires an EU responsible person for a non-EU manufacturer';
        END IF;
        IF NEW.ce_required=1 AND NEW.ce_confirmed=0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'CE-required product cannot be approved without confirmation';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_compliance_product_approval_guard_update
BEFORE UPDATE ON compliance_product_markets
FOR EACH ROW
BEGIN
    IF NEW.approval_status='approved' THEN
        IF NEW.product_identifier='' OR NEW.manufacturer_name='' OR
           NEW.manufacturer_postal_address='' OR NEW.manufacturer_email='' OR
           NEW.safety_warnings_de IS NULL OR NEW.safety_warnings_de='' OR
           NEW.delivery_min_days IS NULL OR NEW.delivery_max_days IS NULL OR
           NEW.delivery_max_days < NEW.delivery_min_days
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Approved products require manufacturer, safety and delivery data';
        END IF;
        IF NEW.manufacturer_outside_eu=1 AND NEW.country_code IN ('AT','DE') AND
           (NEW.eu_responsible_person_name IS NULL OR NEW.eu_responsible_person_name='' OR
            NEW.eu_responsible_person_postal_address IS NULL OR NEW.eu_responsible_person_postal_address='' OR
            NEW.eu_responsible_person_email IS NULL OR NEW.eu_responsible_person_email='')
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'EU product offer requires an EU responsible person for a non-EU manufacturer';
        END IF;
        IF NEW.ce_required=1 AND NEW.ce_confirmed=0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'CE-required product cannot be approved without confirmation';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_office_documents_compliance_before_final
BEFORE UPDATE ON office_documents
FOR EACH ROW
BEGIN
    DECLARE approved_decisions INT DEFAULT 0;
    DECLARE billing_country CHAR(2);
    DECLARE enabled_market INT DEFAULT 0;

    IF OLD.document_status <> 'final' AND NEW.document_status='final' AND
       NEW.document_type IN ('invoice','credit_note')
    THEN
        SET billing_country = UPPER(COALESCE(
            JSON_UNQUOTE(JSON_EXTRACT(NEW.billing_json,'$.country')),
            JSON_UNQUOTE(JSON_EXTRACT(NEW.shipping_json,'$.country')),
            'AT'
        ));

        SELECT COUNT(*) INTO enabled_market
          FROM compliance_market_profiles
         WHERE country_code=billing_country
           AND legal_review_status='approved' AND tax_review_status='approved'
           AND ((NEW.customer_type='business' AND b2b_enabled=1) OR
                (NEW.customer_type<>'business' AND b2c_enabled=1));

        IF enabled_market=0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Final invoice blocked: destination market is not compliance-approved';
        END IF;

        SELECT COUNT(*) INTO approved_decisions
          FROM compliance_tax_decisions
         WHERE document_id=NEW.id AND decision_status='approved';

        IF approved_decisions <> 1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Final invoice blocked: exactly one approved tax decision is required';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_office_documents_compliance_archive
AFTER UPDATE ON office_documents
FOR EACH ROW
BEGIN
    DECLARE jurisdiction CHAR(2);
    DECLARE retention_years INT DEFAULT 7;
    DECLARE retention_date DATE;

    IF OLD.document_status <> 'final' AND NEW.document_status='final' AND
       NEW.pdf_sha256 IS NOT NULL AND NEW.document_number IS NOT NULL
    THEN
        SET jurisdiction = UPPER(COALESCE(
            JSON_UNQUOTE(JSON_EXTRACT(NEW.billing_json,'$.country')),
            JSON_UNQUOTE(JSON_EXTRACT(NEW.shipping_json,'$.country')),
            'AT'
        ));
        SELECT COALESCE(MAX(accounting_retention_years),7) INTO retention_years
          FROM compliance_market_profiles
         WHERE country_code IN ('AT', jurisdiction);
        SET retention_date = STR_TO_DATE(CONCAT(YEAR(NEW.issue_date)+retention_years,'-12-31'),'%Y-%m-%d');

        INSERT IGNORE INTO compliance_document_archive
        (document_id,jurisdiction_country,document_type,document_number,document_sha256,retention_until)
        VALUES
        (NEW.id,jurisdiction,NEW.document_type,NEW.document_number,NEW.pdf_sha256,retention_date);
    END IF;
END//

DELIMITER ;
