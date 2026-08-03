DROP TRIGGER IF EXISTS trg_compliance_legal_evidence_update;
DROP TRIGGER IF EXISTS trg_office_documents_compliance_before_rendering;

DELIMITER //

CREATE TRIGGER trg_compliance_legal_evidence_update
BEFORE UPDATE ON compliance_legal_documents
FOR EACH ROW
BEGIN
    DECLARE durable_required INT DEFAULT 0;
    SELECT COALESCE(MAX(must_be_durable_medium),0) INTO durable_required
      FROM compliance_market_required_documents
     WHERE country_code=NEW.country_code AND document_type=NEW.document_type;

    -- An old approved version may be deactivated so that a new evidenced
    -- version can replace it. Evidence remains mandatory for every active
    -- approved version.
    IF NEW.approval_status='approved' AND NEW.active=1 THEN
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

CREATE TRIGGER trg_office_documents_compliance_before_rendering
BEFORE UPDATE ON office_documents
FOR EACH ROW
BEGIN
    DECLARE approved_decisions INT DEFAULT 0;
    DECLARE decision_country CHAR(2);
    DECLARE decision_scheme VARCHAR(64);
    DECLARE enabled_market INT DEFAULT 0;

    IF OLD.document_status<>'rendering' AND NEW.document_status='rendering' AND
       NEW.document_type IN ('invoice','credit_note')
    THEN
        SELECT COUNT(*),MAX(destination_country),MAX(tax_scheme)
          INTO approved_decisions,decision_country,decision_scheme
          FROM compliance_tax_decisions
         WHERE document_id=NEW.id AND decision_status='approved';

        IF approved_decisions<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Invoice rendering blocked before number allocation: exactly one approved tax decision is required';
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
    END IF;
END//

DELIMITER ;
