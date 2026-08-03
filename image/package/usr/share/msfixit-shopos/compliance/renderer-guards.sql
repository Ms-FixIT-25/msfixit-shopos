CREATE TABLE IF NOT EXISTS compliance_capabilities (
    capability_code VARCHAR(96) NOT NULL PRIMARY KEY,
    capability_version VARCHAR(32) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 0,
    verified_at TIMESTAMP NULL DEFAULT NULL,
    verified_by VARCHAR(191) NULL,
    evidence_path VARCHAR(512) NULL,
    evidence_sha256 CHAR(64) NULL,
    notes VARCHAR(1000) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO compliance_capabilities
(capability_code,capability_version,enabled,notes)
VALUES
('advanced_b2b_tax_invoice_renderer','0.5.0',0,'Required for intra-Community supply, reverse charge and cross-border exemption notices plus buyer VAT ID rendering.'),
('structured_en16931_invoice_renderer','0.5.0',0,'Required before ShopOS may claim XRechnung, ZUGFeRD or another EN-16931 structured invoice.'),
('chf_country_aware_price_renderer','0.5.0',0,'Required for simultaneous legally reviewed CHF consumer pricing while AT/DE remain in EUR.')
ON DUPLICATE KEY UPDATE capability_version=VALUES(capability_version),notes=VALUES(notes);

DROP TRIGGER IF EXISTS trg_compliance_capability_guard_insert;
DROP TRIGGER IF EXISTS trg_compliance_capability_guard_update;
DROP TRIGGER IF EXISTS trg_office_documents_compliance_before_rendering;
DROP TRIGGER IF EXISTS trg_office_documents_compliance_before_final;

DELIMITER //

CREATE TRIGGER trg_compliance_capability_guard_insert
BEFORE INSERT ON compliance_capabilities
FOR EACH ROW
BEGIN
    IF NEW.enabled=1 AND
       (NEW.verified_at IS NULL OR NEW.verified_by IS NULL OR NEW.verified_by='' OR
        NEW.evidence_path IS NULL OR NEW.evidence_path='' OR
        NEW.evidence_sha256 IS NULL OR NEW.evidence_sha256 NOT REGEXP '^[0-9a-f]{64}$')
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Enabled compliance capability requires verified actor and hashed test evidence';
    END IF;
END//

CREATE TRIGGER trg_compliance_capability_guard_update
BEFORE UPDATE ON compliance_capabilities
FOR EACH ROW
BEGIN
    IF NEW.enabled=1 AND
       (NEW.verified_at IS NULL OR NEW.verified_by IS NULL OR NEW.verified_by='' OR
        NEW.evidence_path IS NULL OR NEW.evidence_path='' OR
        NEW.evidence_sha256 IS NULL OR NEW.evidence_sha256 NOT REGEXP '^[0-9a-f]{64}$')
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Enabled compliance capability requires verified actor and hashed test evidence';
    END IF;
END//

CREATE TRIGGER trg_office_documents_compliance_before_rendering
BEFORE UPDATE ON office_documents
FOR EACH ROW
BEGIN
    DECLARE approved_decisions INT DEFAULT 0;
    DECLARE decision_country CHAR(2);
    DECLARE decision_scheme VARCHAR(64);
    DECLARE structured_requirement VARCHAR(64);
    DECLARE enabled_market INT DEFAULT 0;
    DECLARE advanced_renderer INT DEFAULT 0;
    DECLARE structured_renderer INT DEFAULT 0;

    IF OLD.document_status<>'rendering' AND NEW.document_status='rendering' AND
       NEW.document_type IN ('invoice','credit_note')
    THEN
        SELECT COUNT(*),MAX(destination_country),MAX(tax_scheme),MAX(structured_invoice_requirement)
          INTO approved_decisions,decision_country,decision_scheme,structured_requirement
          FROM compliance_tax_decisions
         WHERE document_id=NEW.id AND decision_status='approved'
           AND COALESCE(is_current,1)=1;

        IF approved_decisions<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Invoice rendering blocked before number allocation: exactly one current approved tax decision is required';
        END IF;
        IF decision_scheme<>NEW.tax_mode THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Invoice rendering blocked: document tax mode differs from approved tax decision';
        END IF;

        SELECT COUNT(*) INTO enabled_market
          FROM compliance_market_profiles
         WHERE country_code=decision_country
           AND legal_review_status='approved' AND tax_review_status='approved'
           AND ((NEW.customer_type='business' AND b2b_enabled=1) OR
                (NEW.customer_type<>'business' AND b2c_enabled=1));
        IF enabled_market=0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Invoice rendering blocked: tax destination market is not approved';
        END IF;

        SELECT COUNT(*) INTO advanced_renderer
          FROM compliance_capabilities
         WHERE capability_code='advanced_b2b_tax_invoice_renderer' AND enabled=1;
        SELECT COUNT(*) INTO structured_renderer
          FROM compliance_capabilities
         WHERE capability_code='structured_en16931_invoice_renderer' AND enabled=1;

        IF decision_scheme IN ('intra_community_supply','reverse_charge','eu_small_business_exempt','de_small_business_exempt')
           AND advanced_renderer=0
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Invoice rendering blocked: selected tax scheme needs the advanced DACH tax invoice renderer';
        END IF;
        IF decision_country<>'AT' AND decision_scheme='at_small_business_exempt' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Invoice rendering blocked: Austrian small-business notice cannot be used for a foreign exemption decision';
        END IF;
        IF structured_requirement<>'not_required' AND structured_renderer=0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Invoice rendering blocked: structured invoice requirement has no verified renderer';
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
    DECLARE structured_requirement VARCHAR(64);
    DECLARE enabled_market INT DEFAULT 0;
    DECLARE advanced_renderer INT DEFAULT 0;
    DECLARE structured_renderer INT DEFAULT 0;

    IF OLD.document_status<>'final' AND NEW.document_status='final' AND
       NEW.document_type IN ('invoice','credit_note')
    THEN
        SELECT COUNT(*),MAX(destination_country),MAX(tax_scheme),MAX(structured_invoice_requirement)
          INTO approved_decisions,decision_country,decision_scheme,structured_requirement
          FROM compliance_tax_decisions
         WHERE document_id=NEW.id AND decision_status='approved'
           AND COALESCE(is_current,1)=1;

        IF approved_decisions<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Final invoice blocked: exactly one current approved tax decision is required';
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

        SELECT COUNT(*) INTO advanced_renderer
          FROM compliance_capabilities
         WHERE capability_code='advanced_b2b_tax_invoice_renderer' AND enabled=1;
        SELECT COUNT(*) INTO structured_renderer
          FROM compliance_capabilities
         WHERE capability_code='structured_en16931_invoice_renderer' AND enabled=1;

        IF decision_scheme IN ('intra_community_supply','reverse_charge','eu_small_business_exempt','de_small_business_exempt')
           AND advanced_renderer=0
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Final invoice blocked: selected tax scheme needs the advanced DACH tax invoice renderer';
        END IF;
        IF decision_country<>'AT' AND decision_scheme='at_small_business_exempt' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Final invoice blocked: Austrian small-business notice cannot be used for a foreign exemption decision';
        END IF;
        IF structured_requirement<>'not_required' AND structured_renderer=0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Final invoice blocked: structured invoice requirement has no verified renderer';
        END IF;
    END IF;
END//

DELIMITER ;
