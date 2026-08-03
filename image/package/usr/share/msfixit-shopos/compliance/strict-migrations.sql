DROP TRIGGER IF EXISTS trg_compliance_legal_evidence_update;

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

DELIMITER ;
