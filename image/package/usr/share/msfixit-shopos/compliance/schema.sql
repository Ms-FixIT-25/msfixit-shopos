CREATE TABLE IF NOT EXISTS compliance_schema_versions (
    version_number INT UNSIGNED NOT NULL PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO compliance_schema_versions (version_number) VALUES (1);

CREATE TABLE IF NOT EXISTS compliance_market_profiles (
    country_code CHAR(2) NOT NULL PRIMARY KEY,
    market_name VARCHAR(96) NOT NULL,
    seller_establishment_country CHAR(2) NOT NULL DEFAULT 'AT',
    settlement_currency CHAR(3) NOT NULL,
    b2c_enabled TINYINT(1) NOT NULL DEFAULT 0,
    b2b_enabled TINYINT(1) NOT NULL DEFAULT 0,
    legal_review_status VARCHAR(24) NOT NULL DEFAULT 'review_required',
    tax_review_status VARCHAR(24) NOT NULL DEFAULT 'review_required',
    product_review_status VARCHAR(24) NOT NULL DEFAULT 'review_required',
    withdrawal_policy VARCHAR(48) NOT NULL,
    withdrawal_days SMALLINT UNSIGNED NULL,
    withdrawal_function_required_from DATE NULL,
    price_display_policy VARCHAR(64) NOT NULL,
    structured_invoice_policy VARCHAR(64) NOT NULL,
    accounting_retention_years SMALLINT UNSIGNED NOT NULL,
    approved_at TIMESTAMP NULL DEFAULT NULL,
    approved_by VARCHAR(191) NULL,
    suspended_reason VARCHAR(500) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO compliance_market_profiles
(country_code, market_name, settlement_currency, withdrawal_policy, withdrawal_days,
 withdrawal_function_required_from, price_display_policy, structured_invoice_policy,
 accounting_retention_years)
VALUES
('AT', 'Österreich', 'EUR', 'eu_14_days', 14, '2026-10-01', 'gross_total_eur', 'at_b2g_structured_review', 7),
('DE', 'Deutschland', 'EUR', 'eu_14_days', 14, '2026-06-19', 'gross_total_eur', 'seller_establishment_decision', 8),
('CH', 'Schweiz', 'CHF', 'none_statutory', NULL, NULL, 'gross_total_chf', 'audit_trail_invoice', 10)
ON DUPLICATE KEY UPDATE market_name = VALUES(market_name);

CREATE TABLE IF NOT EXISTS compliance_market_required_documents (
    country_code CHAR(2) NOT NULL,
    document_type VARCHAR(48) NOT NULL,
    required_for_b2c TINYINT(1) NOT NULL DEFAULT 1,
    required_for_b2b TINYINT(1) NOT NULL DEFAULT 1,
    must_be_durable_medium TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (country_code, document_type),
    CONSTRAINT fk_compliance_required_documents_market
        FOREIGN KEY (country_code) REFERENCES compliance_market_profiles (country_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO compliance_market_required_documents
(country_code, document_type, required_for_b2c, required_for_b2b, must_be_durable_medium)
VALUES
('AT','imprint',1,1,0),('AT','terms',1,1,1),('AT','privacy',1,1,0),
('AT','withdrawal',1,0,1),('AT','shipping',1,1,1),('AT','payment',1,1,1),
('AT','warranty_returns',1,1,1),('AT','product_safety',1,1,0),
('DE','imprint',1,1,0),('DE','terms',1,1,1),('DE','privacy',1,1,0),
('DE','withdrawal',1,0,1),('DE','shipping',1,1,1),('DE','payment',1,1,1),
('DE','warranty_returns',1,1,1),('DE','product_safety',1,1,0),
('CH','imprint',1,1,0),('CH','terms',1,1,1),('CH','privacy',1,1,0),
('CH','shipping',1,1,1),('CH','payment',1,1,1),
('CH','warranty_returns',1,1,1),('CH','product_safety',1,1,0);

CREATE TABLE IF NOT EXISTS compliance_legal_documents (
    id CHAR(36) NOT NULL PRIMARY KEY,
    country_code CHAR(2) NOT NULL,
    document_type VARCHAR(48) NOT NULL,
    version_label VARCHAR(64) NOT NULL,
    wp_page_slug VARCHAR(191) NULL,
    content_sha256 CHAR(64) NOT NULL,
    file_path VARCHAR(512) NULL,
    file_sha256 CHAR(64) NULL,
    valid_from DATE NOT NULL,
    valid_until DATE NULL,
    approval_status VARCHAR(24) NOT NULL DEFAULT 'review_required',
    approved_at TIMESTAMP NULL DEFAULT NULL,
    approved_by VARCHAR(191) NULL,
    active TINYINT(1) NOT NULL DEFAULT 0,
    source_notes VARCHAR(1000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_compliance_legal_version (country_code, document_type, version_label),
    KEY ix_compliance_legal_active (country_code, document_type, active),
    CONSTRAINT fk_compliance_legal_market
        FOREIGN KEY (country_code) REFERENCES compliance_market_profiles (country_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_business_registrations (
    id CHAR(36) NOT NULL PRIMARY KEY,
    country_code CHAR(2) NOT NULL,
    legal_entity_code VARCHAR(64) NOT NULL DEFAULT 'seller',
    registration_type VARCHAR(64) NOT NULL,
    registration_number VARCHAR(191) NOT NULL,
    holder_name VARCHAR(255) NOT NULL,
    registration_status VARCHAR(24) NOT NULL DEFAULT 'unverified',
    valid_from DATE NULL,
    valid_until DATE NULL,
    evidence_path VARCHAR(512) NULL,
    evidence_sha256 CHAR(64) NULL,
    verified_at TIMESTAMP NULL DEFAULT NULL,
    verified_by VARCHAR(191) NULL,
    verification_source VARCHAR(500) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_compliance_registration (country_code, legal_entity_code, registration_type),
    KEY ix_compliance_registration_status (country_code, registration_type, registration_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_suppliers (
    supplier_code VARCHAR(64) NOT NULL PRIMARY KEY,
    legal_name VARCHAR(255) NOT NULL,
    country_code CHAR(2) NOT NULL,
    direct_to_customer TINYINT(1) NOT NULL DEFAULT 0,
    dispatcher_legal_entity_code VARCHAR(64) NULL,
    contact_email VARCHAR(255) NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'review_required',
    approved_at TIMESTAMP NULL DEFAULT NULL,
    approved_by VARCHAR(191) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_supplier_markets (
    supplier_code VARCHAR(64) NOT NULL,
    country_code CHAR(2) NOT NULL,
    actual_dispatcher_name VARCHAR(255) NULL,
    packaging_registration VARCHAR(191) NULL,
    packaging_system_participation VARCHAR(191) NULL,
    eee_registration VARCHAR(191) NULL,
    battery_registration VARCHAR(191) NULL,
    authorized_representative VARCHAR(255) NULL,
    verification_status VARCHAR(24) NOT NULL DEFAULT 'review_required',
    verified_at TIMESTAMP NULL DEFAULT NULL,
    verified_by VARCHAR(191) NULL,
    evidence_path VARCHAR(512) NULL,
    evidence_sha256 CHAR(64) NULL,
    PRIMARY KEY (supplier_code, country_code),
    CONSTRAINT fk_compliance_supplier_market_supplier
        FOREIGN KEY (supplier_code) REFERENCES compliance_suppliers (supplier_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_compliance_supplier_market_market
        FOREIGN KEY (country_code) REFERENCES compliance_market_profiles (country_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_product_markets (
    article_number VARCHAR(20) NOT NULL,
    country_code CHAR(2) NOT NULL,
    supplier_code VARCHAR(64) NULL,
    product_identifier VARCHAR(191) NOT NULL,
    manufacturer_name VARCHAR(255) NOT NULL,
    manufacturer_postal_address VARCHAR(500) NOT NULL,
    manufacturer_email VARCHAR(255) NOT NULL,
    eu_responsible_person_name VARCHAR(255) NULL,
    eu_responsible_person_postal_address VARCHAR(500) NULL,
    eu_responsible_person_email VARCHAR(255) NULL,
    manufacturer_outside_eu TINYINT(1) NOT NULL DEFAULT 0,
    safety_warnings_de TEXT NULL,
    safety_warnings_fr TEXT NULL,
    safety_warnings_it TEXT NULL,
    instructions_languages VARCHAR(191) NULL,
    ce_required TINYINT(1) NOT NULL DEFAULT 0,
    ce_confirmed TINYINT(1) NOT NULL DEFAULT 0,
    electrical_equipment TINYINT(1) NOT NULL DEFAULT 0,
    contains_battery TINYINT(1) NOT NULL DEFAULT 0,
    eee_registration_number VARCHAR(191) NULL,
    battery_registration_number VARCHAR(191) NULL,
    delivery_min_days SMALLINT UNSIGNED NULL,
    delivery_max_days SMALLINT UNSIGNED NULL,
    legal_guarantee_months SMALLINT UNSIGNED NULL,
    withdrawal_exception_code VARCHAR(64) NULL,
    economic_operator_role VARCHAR(32) NOT NULL DEFAULT 'retailer',
    approval_status VARCHAR(24) NOT NULL DEFAULT 'review_required',
    approved_at TIMESTAMP NULL DEFAULT NULL,
    approved_by VARCHAR(191) NULL,
    evidence_path VARCHAR(512) NULL,
    evidence_sha256 CHAR(64) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (article_number, country_code),
    KEY ix_compliance_product_status (country_code, approval_status),
    KEY ix_compliance_product_supplier (supplier_code),
    CONSTRAINT fk_compliance_product_market_market
        FOREIGN KEY (country_code) REFERENCES compliance_market_profiles (country_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_compliance_product_market_supplier
        FOREIGN KEY (supplier_code) REFERENCES compliance_suppliers (supplier_code)
        ON UPDATE RESTRICT ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_tax_decisions (
    id CHAR(36) NOT NULL PRIMARY KEY,
    document_id CHAR(36) NULL,
    source_system VARCHAR(48) NOT NULL,
    source_order_id VARCHAR(191) NOT NULL,
    seller_establishment_country CHAR(2) NOT NULL,
    destination_country CHAR(2) NOT NULL,
    customer_type VARCHAR(24) NOT NULL,
    customer_vat_id VARCHAR(64) NULL,
    vat_id_validation_status VARCHAR(24) NULL,
    tax_scheme VARCHAR(64) NOT NULL,
    tax_rate DECIMAL(7,4) NULL,
    structured_invoice_requirement VARCHAR(64) NOT NULL DEFAULT 'not_required',
    decision_status VARCHAR(24) NOT NULL DEFAULT 'review_required',
    decision_reason VARCHAR(1000) NOT NULL,
    decided_at TIMESTAMP NULL DEFAULT NULL,
    decided_by VARCHAR(191) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_compliance_tax_source (source_system, source_order_id),
    KEY ix_compliance_tax_document (document_id),
    CONSTRAINT fk_compliance_tax_document
        FOREIGN KEY (document_id) REFERENCES office_documents (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_checkout_snapshots (
    id CHAR(36) NOT NULL PRIMARY KEY,
    source_order_id VARCHAR(191) NOT NULL,
    country_code CHAR(2) NOT NULL,
    customer_type VARCHAR(24) NOT NULL,
    currency CHAR(3) NOT NULL,
    gross_total DECIMAL(15,4) NOT NULL,
    shipping_total DECIMAL(15,4) NOT NULL DEFAULT 0,
    button_label VARCHAR(191) NOT NULL,
    payment_method VARCHAR(191) NULL,
    delivery_promise VARCHAR(255) NULL,
    legal_documents_json JSON NOT NULL,
    product_compliance_json JSON NOT NULL,
    consent_json JSON NULL,
    snapshot_sha256 CHAR(64) NOT NULL,
    captured_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_compliance_checkout_source (source_order_id),
    KEY ix_compliance_checkout_country (country_code, captured_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_withdrawals (
    id CHAR(36) NOT NULL PRIMARY KEY,
    source_order_id VARCHAR(191) NOT NULL,
    country_code CHAR(2) NOT NULL,
    requester_name VARCHAR(255) NOT NULL,
    requester_email VARCHAR(255) NOT NULL,
    requested_items_json JSON NULL,
    declaration_text TEXT NOT NULL,
    request_sha256 CHAR(64) NOT NULL,
    request_status VARCHAR(32) NOT NULL DEFAULT 'received',
    requested_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    confirmation_sent_at TIMESTAMP NULL DEFAULT NULL,
    refund_due_at TIMESTAMP NULL DEFAULT NULL,
    completed_at TIMESTAMP NULL DEFAULT NULL,
    last_status_note VARCHAR(1000) NULL,
    UNIQUE KEY uq_compliance_withdrawal_hash (request_sha256),
    KEY ix_compliance_withdrawal_order (source_order_id),
    KEY ix_compliance_withdrawal_status (request_status, requested_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_document_archive (
    document_id CHAR(36) NOT NULL PRIMARY KEY,
    jurisdiction_country CHAR(2) NOT NULL,
    document_type VARCHAR(32) NOT NULL,
    document_number VARCHAR(48) NOT NULL,
    document_sha256 CHAR(64) NOT NULL,
    retention_until DATE NOT NULL,
    legal_hold TINYINT(1) NOT NULL DEFAULT 0,
    legal_hold_reason VARCHAR(500) NULL,
    archived_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_compliance_archive_document
        FOREIGN KEY (document_id) REFERENCES office_documents (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_sales_counters (
    calendar_year SMALLINT UNSIGNED NOT NULL,
    counter_type VARCHAR(48) NOT NULL,
    destination_country CHAR(2) NOT NULL DEFAULT '**',
    currency CHAR(3) NOT NULL DEFAULT 'EUR',
    amount_original DECIMAL(18,4) NOT NULL DEFAULT 0,
    amount_eur DECIMAL(18,4) NOT NULL DEFAULT 0,
    item_count BIGINT UNSIGNED NOT NULL DEFAULT 0,
    exchange_rate_source VARCHAR(255) NULL,
    exchange_rate_date DATE NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (calendar_year, counter_type, destination_country)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS compliance_threshold_rules (
    rule_code VARCHAR(64) NOT NULL PRIMARY KEY,
    jurisdiction VARCHAR(8) NOT NULL,
    threshold_amount DECIMAL(18,4) NOT NULL,
    tolerance_amount DECIMAL(18,4) NULL,
    currency CHAR(3) NOT NULL DEFAULT 'EUR',
    effective_from DATE NOT NULL,
    effective_until DATE NULL,
    enforcement_action VARCHAR(48) NOT NULL DEFAULT 'review_required',
    source_reviewed_on DATE NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO compliance_threshold_rules
(rule_code, jurisdiction, threshold_amount, tolerance_amount, currency, effective_from,
 enforcement_action, source_reviewed_on, enabled)
VALUES
('AT_SMALL_BUSINESS', 'AT', 55000, 60500, 'EUR', '2025-01-01', 'block_exemption_above_tolerance', '2026-08-03', 1),
('EU_B2C_DISTANCE_SALES', 'EU', 10000, NULL, 'EUR', '2021-07-01', 'require_oss_or_destination_vat', '2026-08-03', 1),
('EU_SME_CROSS_BORDER', 'EU', 100000, NULL, 'EUR', '2025-01-01', 'block_cross_border_exemption', '2026-08-03', 1),
('EU_LOW_VALUE_IMPORT', 'EU', 150, 3, 'EUR', '2026-07-01', 'customs_landed_cost_review', '2026-08-03', 1)
ON DUPLICATE KEY UPDATE source_reviewed_on = VALUES(source_reviewed_on);

CREATE TABLE IF NOT EXISTS compliance_audit_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_uuid CHAR(36) NOT NULL,
    actor_type VARCHAR(32) NOT NULL,
    actor_reference VARCHAR(191) NULL,
    event_type VARCHAR(96) NOT NULL,
    object_type VARCHAR(64) NOT NULL,
    object_reference VARCHAR(191) NOT NULL,
    event_payload_json JSON NOT NULL,
    previous_event_sha256 CHAR(64) NULL,
    event_sha256 CHAR(64) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_compliance_audit_uuid (event_uuid),
    UNIQUE KEY uq_compliance_audit_hash (event_sha256),
    KEY ix_compliance_audit_object (object_type, object_reference, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS trg_compliance_legal_approved_immutable_update;
DROP TRIGGER IF EXISTS trg_compliance_legal_no_delete;
DROP TRIGGER IF EXISTS trg_compliance_checkout_immutable_update;
DROP TRIGGER IF EXISTS trg_compliance_checkout_no_delete;
DROP TRIGGER IF EXISTS trg_compliance_tax_approved_immutable_update;
DROP TRIGGER IF EXISTS trg_compliance_tax_no_delete;
DROP TRIGGER IF EXISTS trg_compliance_archive_guard_update;
DROP TRIGGER IF EXISTS trg_compliance_archive_no_delete;
DROP TRIGGER IF EXISTS trg_compliance_audit_no_update;
DROP TRIGGER IF EXISTS trg_compliance_audit_no_delete;

DELIMITER //

CREATE TRIGGER trg_compliance_legal_approved_immutable_update
BEFORE UPDATE ON compliance_legal_documents
FOR EACH ROW
BEGIN
    IF OLD.approval_status = 'approved' AND OLD.active = 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Active approved legal documents are immutable; approve a new version';
    END IF;
END//

CREATE TRIGGER trg_compliance_legal_no_delete
BEFORE DELETE ON compliance_legal_documents
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Legal document versions cannot be deleted';
END//

CREATE TRIGGER trg_compliance_checkout_immutable_update
BEFORE UPDATE ON compliance_checkout_snapshots
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Checkout compliance snapshots are immutable';
END//

CREATE TRIGGER trg_compliance_checkout_no_delete
BEFORE DELETE ON compliance_checkout_snapshots
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Checkout compliance snapshots cannot be deleted';
END//

CREATE TRIGGER trg_compliance_tax_approved_immutable_update
BEFORE UPDATE ON compliance_tax_decisions
FOR EACH ROW
BEGIN
    IF OLD.decision_status = 'approved' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Approved tax decisions are immutable; create a replacement decision';
    END IF;
END//

CREATE TRIGGER trg_compliance_tax_no_delete
BEFORE DELETE ON compliance_tax_decisions
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tax decisions cannot be deleted';
END//

CREATE TRIGGER trg_compliance_archive_guard_update
BEFORE UPDATE ON compliance_document_archive
FOR EACH ROW
BEGIN
    IF NEW.document_id <> OLD.document_id OR
       NEW.jurisdiction_country <> OLD.jurisdiction_country OR
       NEW.document_type <> OLD.document_type OR
       NEW.document_number <> OLD.document_number OR
       NEW.document_sha256 <> OLD.document_sha256 OR
       NEW.retention_until < OLD.retention_until OR
       (OLD.legal_hold = 1 AND NEW.legal_hold = 0)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Archive records may only extend retention or legal hold';
    END IF;
END//

CREATE TRIGGER trg_compliance_archive_no_delete
BEFORE DELETE ON compliance_document_archive
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Archived commercial documents cannot be deleted';
END//

CREATE TRIGGER trg_compliance_audit_no_update
BEFORE UPDATE ON compliance_audit_log
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Compliance audit log is append-only';
END//

CREATE TRIGGER trg_compliance_audit_no_delete
BEFORE DELETE ON compliance_audit_log
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Compliance audit log is append-only';
END//

DELIMITER ;
