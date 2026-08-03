CREATE TABLE IF NOT EXISTS office_schema_versions (
    version_number INT UNSIGNED NOT NULL PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO office_schema_versions (version_number) VALUES (1);

CREATE TABLE IF NOT EXISTS office_sequences (
    sequence_name VARCHAR(64) NOT NULL,
    sequence_year SMALLINT UNSIGNED NOT NULL,
    next_value BIGINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (sequence_name, sequence_year)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_orders (
    id CHAR(36) NOT NULL PRIMARY KEY,
    source_system VARCHAR(48) NOT NULL,
    source_order_id VARCHAR(191) NOT NULL,
    source_order_number VARCHAR(191) NULL,
    order_status VARCHAR(48) NOT NULL,
    customer_type VARCHAR(24) NOT NULL DEFAULT 'consumer',
    billing_country CHAR(2) NULL,
    shipping_country CHAR(2) NULL,
    currency CHAR(3) NOT NULL DEFAULT 'EUR',
    billing_json JSON NOT NULL,
    shipping_json JSON NOT NULL,
    totals_json JSON NOT NULL,
    metadata_json JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_office_orders_source (source_system, source_order_id),
    KEY ix_office_orders_status (order_status),
    KEY ix_office_orders_country (shipping_country)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_documents (
    id CHAR(36) NOT NULL PRIMARY KEY,
    order_id CHAR(36) NULL,
    document_type VARCHAR(32) NOT NULL,
    document_number VARCHAR(48) NULL,
    document_status VARCHAR(24) NOT NULL DEFAULT 'draft',
    language_code VARCHAR(12) NOT NULL DEFAULT 'de_AT',
    currency CHAR(3) NOT NULL DEFAULT 'EUR',
    tax_mode VARCHAR(48) NOT NULL DEFAULT 'review_required',
    issue_date DATE NULL,
    service_date DATE NULL,
    due_date DATE NULL,
    customer_type VARCHAR(24) NOT NULL DEFAULT 'consumer',
    customer_name VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255) NULL,
    billing_json JSON NOT NULL,
    shipping_json JSON NOT NULL,
    net_total DECIMAL(15,4) NOT NULL DEFAULT 0,
    tax_total DECIMAL(15,4) NOT NULL DEFAULT 0,
    gross_total DECIMAL(15,4) NOT NULL DEFAULT 0,
    source_system VARCHAR(48) NOT NULL,
    source_document_id VARCHAR(191) NOT NULL,
    correction_of_id CHAR(36) NULL,
    snapshot_json JSON NOT NULL,
    pdf_path VARCHAR(512) NULL,
    pdf_sha256 CHAR(64) NULL,
    finalized_at TIMESTAMP NULL DEFAULT NULL,
    sent_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_office_documents_number (document_number),
    UNIQUE KEY uq_office_documents_source (source_system, source_document_id, document_type),
    KEY ix_office_documents_order_id (order_id),
    KEY ix_office_documents_type_status (document_type, document_status),
    KEY ix_office_documents_due_date (due_date),
    CONSTRAINT fk_office_documents_order
        FOREIGN KEY (order_id) REFERENCES office_orders (id)
        ON UPDATE RESTRICT ON DELETE SET NULL,
    CONSTRAINT fk_office_documents_correction
        FOREIGN KEY (correction_of_id) REFERENCES office_documents (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_document_lines (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    document_id CHAR(36) NOT NULL,
    line_number SMALLINT UNSIGNED NOT NULL,
    article_number VARCHAR(20) NULL,
    description VARCHAR(1000) NOT NULL,
    quantity DECIMAL(15,3) NOT NULL DEFAULT 1,
    unit VARCHAR(24) NOT NULL DEFAULT 'Stk',
    unit_net DECIMAL(15,4) NOT NULL DEFAULT 0,
    tax_rate DECIMAL(7,4) NOT NULL DEFAULT 0,
    line_net DECIMAL(15,4) NOT NULL DEFAULT 0,
    line_tax DECIMAL(15,4) NOT NULL DEFAULT 0,
    line_gross DECIMAL(15,4) NOT NULL DEFAULT 0,
    metadata_json JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_office_document_lines (document_id, line_number),
    KEY ix_office_document_lines_article (article_number),
    CONSTRAINT fk_office_document_lines_document
        FOREIGN KEY (document_id) REFERENCES office_documents (id)
        ON UPDATE RESTRICT ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_payments (
    id CHAR(36) NOT NULL PRIMARY KEY,
    payment_source VARCHAR(48) NOT NULL,
    external_payment_id VARCHAR(191) NOT NULL,
    paid_at TIMESTAMP NOT NULL,
    amount DECIMAL(15,4) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'EUR',
    payer_name VARCHAR(255) NULL,
    payer_reference VARCHAR(255) NULL,
    payment_status VARCHAR(24) NOT NULL DEFAULT 'confirmed',
    raw_payload_json JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_office_payments_external (payment_source, external_payment_id),
    KEY ix_office_payments_paid_at (paid_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_payment_allocations (
    payment_id CHAR(36) NOT NULL,
    document_id CHAR(36) NOT NULL,
    allocated_amount DECIMAL(15,4) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (payment_id, document_id),
    CONSTRAINT fk_office_allocations_payment
        FOREIGN KEY (payment_id) REFERENCES office_payments (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_office_allocations_document
        FOREIGN KEY (document_id) REFERENCES office_documents (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_reminder_rules (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    customer_type VARCHAR(24) NOT NULL,
    country_code CHAR(2) NOT NULL,
    reminder_level SMALLINT UNSIGNED NOT NULL,
    days_after_due SMALLINT UNSIGNED NOT NULL,
    payment_period_days SMALLINT UNSIGNED NOT NULL DEFAULT 7,
    fixed_fee DECIMAL(15,4) NOT NULL DEFAULT 0,
    annual_interest_rate DECIMAL(9,6) NOT NULL DEFAULT 0,
    enabled TINYINT(1) NOT NULL DEFAULT 0,
    requires_manual_approval TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_office_reminder_rule (customer_type, country_code, reminder_level)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO office_reminder_rules
(customer_type, country_code, reminder_level, days_after_due, payment_period_days, fixed_fee, annual_interest_rate, enabled, requires_manual_approval)
VALUES
('consumer', 'AT', 0, 3, 7, 0, 0, 1, 0),
('consumer', 'AT', 1, 10, 7, 0, 0, 1, 1),
('consumer', 'AT', 2, 17, 7, 0, 0, 1, 1),
('business', 'AT', 0, 3, 7, 0, 0, 1, 0),
('business', 'AT', 1, 10, 7, 0, 0, 1, 1),
('business', 'AT', 2, 17, 7, 0, 0, 1, 1),
('consumer', 'DE', 0, 3, 7, 0, 0, 1, 0),
('consumer', 'DE', 1, 10, 7, 0, 0, 1, 1),
('consumer', 'DE', 2, 17, 7, 0, 0, 1, 1),
('business', 'DE', 0, 3, 7, 0, 0, 1, 0),
('business', 'DE', 1, 10, 7, 0, 0, 1, 1),
('business', 'DE', 2, 17, 7, 0, 0, 1, 1),
('consumer', 'CH', 0, 3, 7, 0, 0, 1, 0),
('consumer', 'CH', 1, 10, 7, 0, 0, 1, 1),
('consumer', 'CH', 2, 17, 7, 0, 0, 1, 1),
('business', 'CH', 0, 3, 7, 0, 0, 1, 0),
('business', 'CH', 1, 10, 7, 0, 0, 1, 1),
('business', 'CH', 2, 17, 7, 0, 0, 1, 1);

CREATE TABLE IF NOT EXISTS office_reminders (
    id CHAR(36) NOT NULL PRIMARY KEY,
    document_id CHAR(36) NOT NULL,
    reminder_level SMALLINT UNSIGNED NOT NULL,
    reminder_number VARCHAR(48) NULL,
    reminder_status VARCHAR(24) NOT NULL DEFAULT 'pending',
    reminder_date DATE NOT NULL,
    new_due_date DATE NOT NULL,
    principal_amount DECIMAL(15,4) NOT NULL,
    fee_amount DECIMAL(15,4) NOT NULL DEFAULT 0,
    interest_amount DECIMAL(15,4) NOT NULL DEFAULT 0,
    total_amount DECIMAL(15,4) NOT NULL,
    pdf_path VARCHAR(512) NULL,
    pdf_sha256 CHAR(64) NULL,
    approved_at TIMESTAMP NULL DEFAULT NULL,
    sent_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_office_reminders_level (document_id, reminder_level),
    UNIQUE KEY uq_office_reminders_number (reminder_number),
    KEY ix_office_reminders_status (reminder_status),
    CONSTRAINT fk_office_reminders_document
        FOREIGN KEY (document_id) REFERENCES office_documents (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_shipments (
    id CHAR(36) NOT NULL PRIMARY KEY,
    order_id CHAR(36) NOT NULL,
    shipment_number VARCHAR(48) NULL,
    carrier_code VARCHAR(48) NOT NULL,
    carrier_product VARCHAR(96) NULL,
    carrier_shipment_id VARCHAR(191) NULL,
    tracking_number VARCHAR(191) NULL,
    shipment_status VARCHAR(32) NOT NULL DEFAULT 'draft',
    ship_date DATE NULL,
    sender_json JSON NOT NULL,
    recipient_json JSON NOT NULL,
    customs_json JSON NULL,
    label_format VARCHAR(24) NOT NULL DEFAULT 'PDF_A6',
    label_path VARCHAR(512) NULL,
    label_sha256 CHAR(64) NULL,
    raw_response_json JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_office_shipments_number (shipment_number),
    UNIQUE KEY uq_office_shipments_carrier_id (carrier_code, carrier_shipment_id),
    KEY ix_office_shipments_order (order_id),
    KEY ix_office_shipments_tracking (tracking_number),
    KEY ix_office_shipments_status (shipment_status),
    CONSTRAINT fk_office_shipments_order
        FOREIGN KEY (order_id) REFERENCES office_orders (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_packages (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    shipment_id CHAR(36) NOT NULL,
    package_number SMALLINT UNSIGNED NOT NULL,
    weight_kg DECIMAL(10,3) NOT NULL,
    length_cm DECIMAL(10,2) NULL,
    width_cm DECIMAL(10,2) NULL,
    height_cm DECIMAL(10,2) NULL,
    contents_description VARCHAR(500) NULL,
    value_amount DECIMAL(15,4) NULL,
    value_currency CHAR(3) NULL,
    metadata_json JSON NULL,
    UNIQUE KEY uq_office_packages (shipment_id, package_number),
    CONSTRAINT fk_office_packages_shipment
        FOREIGN KEY (shipment_id) REFERENCES office_shipments (id)
        ON UPDATE RESTRICT ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_carrier_accounts (
    carrier_code VARCHAR(48) NOT NULL PRIMARY KEY,
    account_reference VARCHAR(191) NULL,
    origin_country CHAR(2) NOT NULL DEFAULT 'AT',
    adapter_mode VARCHAR(32) NOT NULL DEFAULT 'disabled',
    default_label_format VARCHAR(24) NOT NULL DEFAULT 'PDF_A6',
    default_printer VARCHAR(191) NULL,
    configuration_json JSON NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO office_carrier_accounts
(carrier_code, origin_country, adapter_mode, default_label_format, enabled)
VALUES
('post_at', 'AT', 'plc_or_contract_api', 'PDF_A6', 0),
('dpd_at', 'AT', 'contract_api', 'PDF_A6', 0),
('gls_at', 'AT', 'shipit_api', 'PDF_A6', 0),
('ups', 'AT', 'oauth_api', 'PDF_A6', 0),
('dhl_de', 'DE', 'contract_api', 'PDF_A6', 0);

CREATE TABLE IF NOT EXISTS office_print_jobs (
    id CHAR(36) NOT NULL PRIMARY KEY,
    document_kind VARCHAR(32) NOT NULL,
    source_id CHAR(36) NOT NULL,
    file_path VARCHAR(512) NOT NULL,
    printer_name VARCHAR(191) NOT NULL,
    copies SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    print_status VARCHAR(24) NOT NULL DEFAULT 'pending',
    cups_job_id VARCHAR(64) NULL,
    attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    last_error VARCHAR(1000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    printed_at TIMESTAMP NULL DEFAULT NULL,
    KEY ix_office_print_jobs_status (print_status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_prosaldo_exports (
    id CHAR(36) NOT NULL PRIMARY KEY,
    export_period_start DATE NOT NULL,
    export_period_end DATE NOT NULL,
    export_status VARCHAR(24) NOT NULL DEFAULT 'prepared',
    export_path VARCHAR(512) NOT NULL,
    manifest_sha256 CHAR(64) NULL,
    document_count INT UNSIGNED NOT NULL DEFAULT 0,
    marked_imported_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_office_prosaldo_export_period (export_period_start, export_period_end)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS office_outbox (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_uuid CHAR(36) NOT NULL,
    aggregate_type VARCHAR(64) NOT NULL,
    aggregate_id CHAR(36) NOT NULL,
    event_type VARCHAR(96) NOT NULL,
    payload_json JSON NOT NULL,
    event_status VARCHAR(24) NOT NULL DEFAULT 'pending',
    attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    available_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP NULL DEFAULT NULL,
    last_error VARCHAR(1000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_office_outbox_event_uuid (event_uuid),
    KEY ix_office_outbox_status_available (event_status, available_at),
    KEY ix_office_outbox_aggregate (aggregate_type, aggregate_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS trg_office_documents_immutable_final;
DROP TRIGGER IF EXISTS trg_office_documents_no_delete_final;
DROP TRIGGER IF EXISTS trg_office_document_lines_no_update_final;
DROP TRIGGER IF EXISTS trg_office_document_lines_no_delete_final;
DROP TRIGGER IF EXISTS trg_office_sequences_no_decrement;

DELIMITER //

CREATE TRIGGER trg_office_documents_immutable_final
BEFORE UPDATE ON office_documents
FOR EACH ROW
BEGIN
    IF OLD.document_status = 'final' AND (
        NOT (OLD.document_number <=> NEW.document_number) OR
        NOT (OLD.issue_date <=> NEW.issue_date) OR
        NOT (OLD.service_date <=> NEW.service_date) OR
        NOT (OLD.due_date <=> NEW.due_date) OR
        NOT (OLD.tax_mode <=> NEW.tax_mode) OR
        NOT (OLD.billing_json <=> NEW.billing_json) OR
        NOT (OLD.shipping_json <=> NEW.shipping_json) OR
        NOT (OLD.net_total <=> NEW.net_total) OR
        NOT (OLD.tax_total <=> NEW.tax_total) OR
        NOT (OLD.gross_total <=> NEW.gross_total) OR
        NOT (OLD.snapshot_json <=> NEW.snapshot_json) OR
        NOT (OLD.pdf_sha256 <=> NEW.pdf_sha256)
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Final office documents are immutable; create a correction document';
    END IF;
END//

CREATE TRIGGER trg_office_documents_no_delete_final
BEFORE DELETE ON office_documents
FOR EACH ROW
BEGIN
    IF OLD.document_status = 'final' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Final office documents cannot be deleted';
    END IF;
END//

CREATE TRIGGER trg_office_document_lines_no_update_final
BEFORE UPDATE ON office_document_lines
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM office_documents
        WHERE id = OLD.document_id AND document_status = 'final'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Lines of final office documents are immutable';
    END IF;
END//

CREATE TRIGGER trg_office_document_lines_no_delete_final
BEFORE DELETE ON office_document_lines
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM office_documents
        WHERE id = OLD.document_id AND document_status = 'final'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Lines of final office documents cannot be deleted';
    END IF;
END//

CREATE TRIGGER trg_office_sequences_no_decrement
BEFORE UPDATE ON office_sequences
FOR EACH ROW
BEGIN
    IF NEW.next_value < OLD.next_value THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Office document sequences cannot be decremented';
    END IF;
END//

DELIMITER ;
