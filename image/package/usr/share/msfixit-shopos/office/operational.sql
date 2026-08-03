CREATE TABLE IF NOT EXISTS office_document_holds (
    document_id CHAR(36) NOT NULL PRIMARY KEY,
    dunning_blocked TINYINT(1) NOT NULL DEFAULT 0,
    dunning_block_reason VARCHAR(500) NULL,
    collection_blocked TINYINT(1) NOT NULL DEFAULT 0,
    collection_block_reason VARCHAR(500) NULL,
    updated_by VARCHAR(191) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_office_document_holds_document
        FOREIGN KEY (document_id) REFERENCES office_documents (id)
        ON UPDATE RESTRICT ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_dispatch_log (
    id CHAR(36) NOT NULL PRIMARY KEY,
    document_kind VARCHAR(32) NOT NULL,
    source_id CHAR(36) NOT NULL,
    recipient VARCHAR(255) NOT NULL,
    dispatch_channel VARCHAR(24) NOT NULL DEFAULT 'email',
    subject VARCHAR(500) NULL,
    attachment_sha256 CHAR(64) NULL,
    dispatch_status VARCHAR(24) NOT NULL DEFAULT 'pending',
    provider_message_id VARCHAR(255) NULL,
    attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    last_error VARCHAR(1000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dispatched_at TIMESTAMP NULL DEFAULT NULL,
    KEY ix_office_dispatch_log_status (dispatch_status, created_at),
    KEY ix_office_dispatch_log_source (document_kind, source_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS trg_office_documents_immutable_final;
DROP TRIGGER IF EXISTS trg_office_document_lines_no_insert_final;
DROP TRIGGER IF EXISTS trg_office_payments_immutable;
DROP TRIGGER IF EXISTS trg_office_payments_no_delete;
DROP TRIGGER IF EXISTS trg_office_allocations_validate_insert;
DROP TRIGGER IF EXISTS trg_office_allocations_immutable_update;
DROP TRIGGER IF EXISTS trg_office_allocations_no_delete;

DELIMITER //

CREATE TRIGGER trg_office_documents_immutable_final
BEFORE UPDATE ON office_documents
FOR EACH ROW
BEGIN
    IF OLD.document_status = 'final' AND (
        NOT (OLD.order_id <=> NEW.order_id) OR
        NOT (OLD.document_type <=> NEW.document_type) OR
        NOT (OLD.document_number <=> NEW.document_number) OR
        NOT (OLD.document_status <=> NEW.document_status) OR
        NOT (OLD.language_code <=> NEW.language_code) OR
        NOT (OLD.currency <=> NEW.currency) OR
        NOT (OLD.tax_mode <=> NEW.tax_mode) OR
        NOT (OLD.issue_date <=> NEW.issue_date) OR
        NOT (OLD.service_date <=> NEW.service_date) OR
        NOT (OLD.due_date <=> NEW.due_date) OR
        NOT (OLD.customer_type <=> NEW.customer_type) OR
        NOT (OLD.customer_name <=> NEW.customer_name) OR
        NOT (OLD.customer_email <=> NEW.customer_email) OR
        NOT (OLD.billing_json <=> NEW.billing_json) OR
        NOT (OLD.shipping_json <=> NEW.shipping_json) OR
        NOT (OLD.net_total <=> NEW.net_total) OR
        NOT (OLD.tax_total <=> NEW.tax_total) OR
        NOT (OLD.gross_total <=> NEW.gross_total) OR
        NOT (OLD.source_system <=> NEW.source_system) OR
        NOT (OLD.source_document_id <=> NEW.source_document_id) OR
        NOT (OLD.correction_of_id <=> NEW.correction_of_id) OR
        NOT (OLD.snapshot_json <=> NEW.snapshot_json) OR
        NOT (OLD.pdf_path <=> NEW.pdf_path) OR
        NOT (OLD.pdf_sha256 <=> NEW.pdf_sha256) OR
        NOT (OLD.finalized_at <=> NEW.finalized_at)
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Final office documents are immutable; create a correction document';
    END IF;
END//

CREATE TRIGGER trg_office_document_lines_no_insert_final
BEFORE INSERT ON office_document_lines
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM office_documents
        WHERE id = NEW.document_id AND document_status = 'final'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Lines cannot be added to final office documents';
    END IF;
END//

CREATE TRIGGER trg_office_payments_immutable
BEFORE UPDATE ON office_payments
FOR EACH ROW
BEGIN
    IF NOT (OLD.payment_source <=> NEW.payment_source) OR
       NOT (OLD.external_payment_id <=> NEW.external_payment_id) OR
       NOT (OLD.paid_at <=> NEW.paid_at) OR
       NOT (OLD.amount <=> NEW.amount) OR
       NOT (OLD.currency <=> NEW.currency) OR
       NOT (OLD.payer_name <=> NEW.payer_name) OR
       NOT (OLD.payer_reference <=> NEW.payer_reference) OR
       NOT (OLD.payment_status <=> NEW.payment_status) OR
       NOT (OLD.raw_payload_json <=> NEW.raw_payload_json)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Recorded payments are immutable; use a reversal transaction';
    END IF;
END//

CREATE TRIGGER trg_office_payments_no_delete
BEFORE DELETE ON office_payments
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Recorded payments cannot be deleted';
END//

CREATE TRIGGER trg_office_allocations_validate_insert
BEFORE INSERT ON office_payment_allocations
FOR EACH ROW
BEGIN
    DECLARE payment_amount DECIMAL(15,4);
    DECLARE payment_currency CHAR(3);
    DECLARE document_currency CHAR(3);
    DECLARE allocated_total DECIMAL(15,4);

    IF NEW.allocated_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payment allocation must be greater than zero';
    END IF;

    SELECT amount, currency
      INTO payment_amount, payment_currency
      FROM office_payments
     WHERE id = NEW.payment_id;

    SELECT currency
      INTO document_currency
      FROM office_documents
     WHERE id = NEW.document_id;

    IF payment_currency <> document_currency THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payment and document currencies must match';
    END IF;

    SELECT COALESCE(SUM(allocated_amount), 0)
      INTO allocated_total
      FROM office_payment_allocations
     WHERE payment_id = NEW.payment_id;

    IF allocated_total + NEW.allocated_amount > payment_amount + 0.0001 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payment allocations cannot exceed the recorded payment amount';
    END IF;
END//

CREATE TRIGGER trg_office_allocations_immutable_update
BEFORE UPDATE ON office_payment_allocations
FOR EACH ROW
BEGIN
    IF NOT (OLD.payment_id <=> NEW.payment_id) OR
       NOT (OLD.document_id <=> NEW.document_id) OR
       NOT (OLD.allocated_amount <=> NEW.allocated_amount)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payment allocations are immutable; create a reversal allocation';
    END IF;
END//

CREATE TRIGGER trg_office_allocations_no_delete
BEFORE DELETE ON office_payment_allocations
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Payment allocations cannot be deleted';
END//

DELIMITER ;
