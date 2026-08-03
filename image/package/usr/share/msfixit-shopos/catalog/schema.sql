CREATE TABLE IF NOT EXISTS catalog_schema_versions (
    version_number INT UNSIGNED NOT NULL PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO catalog_schema_versions (version_number) VALUES (1);

CREATE TABLE IF NOT EXISTS catalog_sequences (
    sequence_name VARCHAR(64) NOT NULL PRIMARY KEY,
    next_value BIGINT UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO catalog_sequences (sequence_name, next_value)
VALUES ('article_number', 1);

CREATE TABLE IF NOT EXISTS catalog_products (
    id CHAR(36) NOT NULL PRIMARY KEY,
    article_number VARCHAR(20) NOT NULL,
    parent_id CHAR(36) NULL,
    product_type VARCHAR(32) NOT NULL DEFAULT 'simple',
    product_name VARCHAR(255) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    source_of_truth VARCHAR(64) NOT NULL DEFAULT 'shopos',
    version_number BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_catalog_products_article_number (article_number),
    KEY ix_catalog_products_parent_id (parent_id),
    KEY ix_catalog_products_status (status),
    CONSTRAINT fk_catalog_products_parent
        FOREIGN KEY (parent_id) REFERENCES catalog_products (id)
        ON UPDATE RESTRICT ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS catalog_identifiers (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    product_id CHAR(36) NOT NULL,
    namespace VARCHAR(80) NOT NULL,
    external_id VARCHAR(191) NOT NULL,
    is_primary TINYINT(1) NOT NULL DEFAULT 0,
    metadata_json JSON NULL,
    valid_from TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_catalog_identifiers_namespace_external (namespace, external_id),
    UNIQUE KEY uq_catalog_identifiers_product_namespace_external (product_id, namespace, external_id),
    KEY ix_catalog_identifiers_product_id (product_id),
    CONSTRAINT fk_catalog_identifiers_product
        FOREIGN KEY (product_id) REFERENCES catalog_products (id)
        ON UPDATE RESTRICT ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS catalog_supplier_offers (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    product_id CHAR(36) NOT NULL,
    supplier_code VARCHAR(64) NOT NULL,
    supplier_sku VARCHAR(191) NOT NULL,
    purchase_price DECIMAL(15,4) NULL,
    currency CHAR(3) NOT NULL DEFAULT 'EUR',
    stock_quantity DECIMAL(15,3) NULL,
    stock_status VARCHAR(32) NOT NULL DEFAULT 'unknown',
    lead_time_days SMALLINT UNSIGNED NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    raw_payload_json JSON NULL,
    last_seen_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_catalog_supplier_offer (supplier_code, supplier_sku),
    KEY ix_catalog_supplier_offers_product_id (product_id),
    KEY ix_catalog_supplier_offers_active (active),
    CONSTRAINT fk_catalog_supplier_offers_product
        FOREIGN KEY (product_id) REFERENCES catalog_products (id)
        ON UPDATE RESTRICT ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS catalog_channel_listings (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    product_id CHAR(36) NOT NULL,
    channel_code VARCHAR(64) NOT NULL,
    external_id VARCHAR(191) NOT NULL,
    channel_sku VARCHAR(191) NULL,
    listing_status VARCHAR(32) NOT NULL DEFAULT 'draft',
    last_sync_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_catalog_channel_listing (channel_code, external_id),
    KEY ix_catalog_channel_listings_product_id (product_id),
    CONSTRAINT fk_catalog_channel_listings_product
        FOREIGN KEY (product_id) REFERENCES catalog_products (id)
        ON UPDATE RESTRICT ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS catalog_sync_outbox (
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
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_catalog_sync_outbox_event_uuid (event_uuid),
    KEY ix_catalog_sync_outbox_status_available (event_status, available_at),
    KEY ix_catalog_sync_outbox_aggregate (aggregate_type, aggregate_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
