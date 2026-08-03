CREATE TABLE IF NOT EXISTS pilot_schema_versions (
    version_number INT UNSIGNED NOT NULL PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO pilot_schema_versions (version_number) VALUES (1);

CREATE TABLE IF NOT EXISTS supplier_import_runs (
    id CHAR(36) NOT NULL PRIMARY KEY,
    supplier_code VARCHAR(64) NOT NULL,
    source_type VARCHAR(32) NOT NULL,
    source_name VARCHAR(255) NOT NULL,
    source_sha256 CHAR(64) NOT NULL,
    run_status VARCHAR(24) NOT NULL DEFAULT 'running',
    rows_total INT UNSIGNED NOT NULL DEFAULT 0,
    rows_accepted INT UNSIGNED NOT NULL DEFAULT 0,
    rows_quarantined INT UNSIGNED NOT NULL DEFAULT 0,
    rows_updated INT UNSIGNED NOT NULL DEFAULT 0,
    rows_new INT UNSIGNED NOT NULL DEFAULT 0,
    error_json JSON NULL,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP NULL DEFAULT NULL,
    UNIQUE KEY uq_supplier_import_source (supplier_code, source_sha256),
    KEY ix_supplier_import_runs_status (run_status, started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS supplier_feed_items (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    supplier_code VARCHAR(64) NOT NULL,
    supplier_sku VARCHAR(191) NOT NULL,
    linked_product_id CHAR(36) NULL,
    woocommerce_product_id BIGINT UNSIGNED NULL,
    manufacturer_name VARCHAR(255) NULL,
    manufacturer_sku VARCHAR(191) NULL,
    gtin VARCHAR(32) NULL,
    product_name VARCHAR(500) NOT NULL,
    short_description TEXT NULL,
    marketing_description MEDIUMTEXT NULL,
    category_path VARCHAR(1000) NULL,
    purchase_price DECIMAL(15,4) NULL,
    currency CHAR(3) NOT NULL DEFAULT 'EUR',
    stock_quantity DECIMAL(15,3) NULL,
    stock_status VARCHAR(32) NOT NULL DEFAULT 'unknown',
    lead_time_days SMALLINT UNSIGNED NULL,
    image_url VARCHAR(1500) NULL,
    datasheet_url VARCHAR(1500) NULL,
    content_license VARCHAR(32) NOT NULL DEFAULT 'none',
    source_payload_json JSON NOT NULL,
    source_sha256 CHAR(64) NOT NULL,
    review_status VARCHAR(32) NOT NULL DEFAULT 'new',
    review_reason VARCHAR(1000) NULL,
    proposed_sale_price DECIMAL(15,4) NULL,
    price_review_required TINYINT(1) NOT NULL DEFAULT 1,
    compliance_review_required TINYINT(1) NOT NULL DEFAULT 1,
    active TINYINT(1) NOT NULL DEFAULT 1,
    first_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP NULL DEFAULT NULL,
    reviewed_by VARCHAR(191) NULL,
    UNIQUE KEY uq_supplier_feed_item (supplier_code, supplier_sku),
    KEY ix_supplier_feed_review (supplier_code, review_status, active),
    KEY ix_supplier_feed_product (linked_product_id),
    KEY ix_supplier_feed_gtin (gtin),
    CONSTRAINT fk_supplier_feed_product
        FOREIGN KEY (linked_product_id) REFERENCES catalog_products (id)
        ON UPDATE RESTRICT ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS supplier_feed_changes (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    feed_item_id BIGINT UNSIGNED NOT NULL,
    import_run_id CHAR(36) NOT NULL,
    field_name VARCHAR(96) NOT NULL,
    old_value TEXT NULL,
    new_value TEXT NULL,
    requires_review TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_supplier_feed_changes_item (feed_item_id, created_at),
    KEY ix_supplier_feed_changes_review (requires_review, created_at),
    CONSTRAINT fk_supplier_feed_changes_item
        FOREIGN KEY (feed_item_id) REFERENCES supplier_feed_items (id)
        ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_supplier_feed_changes_run
        FOREIGN KEY (import_run_id) REFERENCES supplier_import_runs (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pilot_product_approvals (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    feed_item_id BIGINT UNSIGNED NOT NULL,
    country_code CHAR(2) NOT NULL DEFAULT 'AT',
    approval_status VARCHAR(24) NOT NULL DEFAULT 'pending',
    approved_sale_price DECIMAL(15,4) NULL,
    approved_by VARCHAR(191) NULL,
    approved_at TIMESTAMP NULL DEFAULT NULL,
    notes VARCHAR(1000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_pilot_product_approval (feed_item_id, country_code),
    KEY ix_pilot_approval_status (country_code, approval_status),
    CONSTRAINT fk_pilot_approval_feed_item
        FOREIGN KEY (feed_item_id) REFERENCES supplier_feed_items (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pilot_order_releases (
    id CHAR(36) NOT NULL PRIMARY KEY,
    source_system VARCHAR(48) NOT NULL,
    source_order_id VARCHAR(191) NOT NULL,
    release_status VARCHAR(24) NOT NULL DEFAULT 'pending',
    supplier_code VARCHAR(64) NOT NULL DEFAULT 'also-at',
    purchase_total DECIMAL(15,4) NULL,
    currency CHAR(3) NOT NULL DEFAULT 'EUR',
    checked_price_at TIMESTAMP NULL DEFAULT NULL,
    checked_stock_at TIMESTAMP NULL DEFAULT NULL,
    released_by VARCHAR(191) NULL,
    released_at TIMESTAMP NULL DEFAULT NULL,
    notes VARCHAR(1000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_pilot_order_release (source_system, source_order_id),
    KEY ix_pilot_order_status (release_status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS trg_supplier_feed_no_reassign;
DROP TRIGGER IF EXISTS trg_pilot_approval_no_reopen;
DROP TRIGGER IF EXISTS trg_pilot_order_no_unrelease;

DELIMITER //

CREATE TRIGGER trg_supplier_feed_no_reassign
BEFORE UPDATE ON supplier_feed_items
FOR EACH ROW
BEGIN
    IF OLD.linked_product_id IS NOT NULL AND NEW.linked_product_id <> OLD.linked_product_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Supplier feed item cannot be reassigned to another article';
    END IF;
END//

CREATE TRIGGER trg_pilot_approval_no_reopen
BEFORE UPDATE ON pilot_product_approvals
FOR EACH ROW
BEGIN
    IF OLD.approval_status='approved' AND NEW.approval_status='pending' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Approved pilot product must be suspended or replaced, not reopened';
    END IF;
END//

CREATE TRIGGER trg_pilot_order_no_unrelease
BEFORE UPDATE ON pilot_order_releases
FOR EACH ROW
BEGIN
    IF OLD.release_status='released' AND NEW.release_status NOT IN ('released','cancelled') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Released supplier order cannot return to pending state';
    END IF;
END//

DELIMITER ;
