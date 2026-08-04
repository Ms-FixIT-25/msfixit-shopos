CREATE TABLE IF NOT EXISTS supplier_content_profiles (
    supplier_code VARCHAR(64) NOT NULL PRIMARY KEY,
    content_package VARCHAR(24) NOT NULL DEFAULT 'none',
    language_code VARCHAR(16) NOT NULL DEFAULT 'de-AT',
    contract_status VARCHAR(24) NOT NULL DEFAULT 'unverified',
    media_mode VARCHAR(24) NOT NULL DEFAULT 'remote_only',
    allow_text_import TINYINT(1) NOT NULL DEFAULT 0,
    allow_remote_images TINYINT(1) NOT NULL DEFAULT 0,
    allow_remote_documents TINYINT(1) NOT NULL DEFAULT 0,
    allow_local_image_cache TINYINT(1) NOT NULL DEFAULT 0,
    allow_local_document_cache TINYINT(1) NOT NULL DEFAULT 0,
    verified_at TIMESTAMP NULL DEFAULT NULL,
    verified_by VARCHAR(191) NULL,
    notes VARCHAR(1000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO supplier_content_profiles
(supplier_code, content_package, language_code, contract_status, media_mode)
VALUES ('also-at', 'none', 'de-AT', 'unverified', 'remote_only');

CREATE TABLE IF NOT EXISTS supplier_content_import_runs (
    id CHAR(36) NOT NULL PRIMARY KEY,
    supplier_code VARCHAR(64) NOT NULL,
    source_name VARCHAR(255) NOT NULL,
    source_sha256 CHAR(64) NOT NULL,
    content_package VARCHAR(24) NOT NULL,
    language_code VARCHAR(16) NOT NULL,
    run_status VARCHAR(24) NOT NULL DEFAULT 'running',
    rows_total INT UNSIGNED NOT NULL DEFAULT 0,
    rows_accepted INT UNSIGNED NOT NULL DEFAULT 0,
    rows_quarantined INT UNSIGNED NOT NULL DEFAULT 0,
    rows_updated INT UNSIGNED NOT NULL DEFAULT 0,
    rows_new INT UNSIGNED NOT NULL DEFAULT 0,
    error_json JSON NULL,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP NULL DEFAULT NULL,
    UNIQUE KEY uq_supplier_content_import_source (supplier_code, source_sha256),
    KEY ix_supplier_content_import_status (run_status, started_at),
    CONSTRAINT fk_supplier_content_profile_run
        FOREIGN KEY (supplier_code) REFERENCES supplier_content_profiles (supplier_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS supplier_content_items (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    supplier_code VARCHAR(64) NOT NULL,
    supplier_sku VARCHAR(191) NOT NULL,
    feed_item_id BIGINT UNSIGNED NULL,
    content_package VARCHAR(24) NOT NULL,
    language_code VARCHAR(16) NOT NULL,
    standard_description MEDIUMTEXT NULL,
    marketing_description MEDIUMTEXT NULL,
    selling_points_json JSON NULL,
    features_json JSON NULL,
    specifications_json JSON NULL,
    source_sha256 CHAR(64) NOT NULL,
    review_status VARCHAR(24) NOT NULL DEFAULT 'pending',
    review_reason VARCHAR(1000) NULL,
    reviewed_at TIMESTAMP NULL DEFAULT NULL,
    reviewed_by VARCHAR(191) NULL,
    first_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_supplier_content_item (supplier_code, supplier_sku, language_code),
    KEY ix_supplier_content_review (supplier_code, review_status),
    KEY ix_supplier_content_feed_item (feed_item_id),
    CONSTRAINT fk_supplier_content_profile_item
        FOREIGN KEY (supplier_code) REFERENCES supplier_content_profiles (supplier_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_supplier_content_feed_item
        FOREIGN KEY (feed_item_id) REFERENCES supplier_feed_items (id)
        ON UPDATE RESTRICT ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS supplier_content_assets (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    content_item_id BIGINT UNSIGNED NOT NULL,
    asset_type VARCHAR(24) NOT NULL,
    asset_role VARCHAR(48) NOT NULL DEFAULT 'generic',
    display_order SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    source_url VARCHAR(2000) NOT NULL,
    source_url_hash CHAR(64) GENERATED ALWAYS AS (SHA2(source_url, 256)) STORED,
    mime_hint VARCHAR(96) NULL,
    language_code VARCHAR(16) NULL,
    approval_status VARCHAR(24) NOT NULL DEFAULT 'pending',
    first_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_supplier_content_asset (content_item_id, source_url_hash),
    KEY ix_supplier_content_asset_review (approval_status, asset_type),
    CONSTRAINT fk_supplier_content_asset_item
        FOREIGN KEY (content_item_id) REFERENCES supplier_content_items (id)
        ON UPDATE RESTRICT ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS supplier_content_relations (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    supplier_code VARCHAR(64) NOT NULL,
    source_supplier_sku VARCHAR(191) NOT NULL,
    target_supplier_sku VARCHAR(191) NOT NULL,
    relation_type VARCHAR(48) NOT NULL DEFAULT 'accessory',
    active TINYINT(1) NOT NULL DEFAULT 1,
    first_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_supplier_content_relation
        (supplier_code, source_supplier_sku, target_supplier_sku, relation_type),
    KEY ix_supplier_content_relation_source (supplier_code, source_supplier_sku, active),
    KEY ix_supplier_content_relation_target (supplier_code, target_supplier_sku, active),
    CONSTRAINT fk_supplier_content_relation_profile
        FOREIGN KEY (supplier_code) REFERENCES supplier_content_profiles (supplier_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS supplier_content_changes (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    content_item_id BIGINT UNSIGNED NOT NULL,
    import_run_id CHAR(36) NOT NULL,
    field_name VARCHAR(96) NOT NULL,
    old_value MEDIUMTEXT NULL,
    new_value MEDIUMTEXT NULL,
    requires_review TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_supplier_content_changes_item (content_item_id, created_at),
    KEY ix_supplier_content_changes_review (requires_review, created_at),
    CONSTRAINT fk_supplier_content_change_item
        FOREIGN KEY (content_item_id) REFERENCES supplier_content_items (id)
        ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_supplier_content_change_run
        FOREIGN KEY (import_run_id) REFERENCES supplier_content_import_runs (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS trg_supplier_content_profile_safety;
DROP TRIGGER IF EXISTS trg_supplier_content_item_approval;
DROP TRIGGER IF EXISTS trg_supplier_content_asset_url;
DROP TRIGGER IF EXISTS trg_supplier_content_asset_approval;

DELIMITER //

CREATE TRIGGER trg_supplier_content_profile_safety
BEFORE UPDATE ON supplier_content_profiles
FOR EACH ROW
BEGIN
    IF NEW.media_mode <> 'remote_only'
       OR NEW.allow_local_image_cache <> 0
       OR NEW.allow_local_document_cache <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Local ALSO content caching requires a separately reviewed schema and contract';
    END IF;
    IF NEW.contract_status='verified' AND NEW.content_package='none' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Verified ALSO content contract requires a package';
    END IF;
END//

CREATE TRIGGER trg_supplier_content_item_approval
BEFORE UPDATE ON supplier_content_items
FOR EACH ROW
BEGIN
    DECLARE profile_status VARCHAR(24);
    DECLARE profile_package VARCHAR(24);
    DECLARE text_allowed TINYINT;
    IF NEW.review_status='approved' AND OLD.review_status<>'approved' THEN
        SELECT contract_status,content_package,allow_text_import
          INTO profile_status,profile_package,text_allowed
          FROM supplier_content_profiles
         WHERE supplier_code=NEW.supplier_code;
        IF profile_status<>'verified' OR profile_package='none' OR text_allowed<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='ALSO content cannot be approved without a verified licensed content profile';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_supplier_content_asset_url
BEFORE INSERT ON supplier_content_assets
FOR EACH ROW
BEGIN
    IF NEW.source_url NOT LIKE 'https://%' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='ALSO content assets require HTTPS URLs';
    END IF;
END//

CREATE TRIGGER trg_supplier_content_asset_approval
BEFORE UPDATE ON supplier_content_assets
FOR EACH ROW
BEGIN
    DECLARE supplier VARCHAR(64);
    DECLARE profile_status VARCHAR(24);
    DECLARE images_allowed TINYINT;
    DECLARE documents_allowed TINYINT;
    IF NEW.approval_status='approved' AND OLD.approval_status<>'approved' THEN
        SELECT i.supplier_code INTO supplier
          FROM supplier_content_items i WHERE i.id=NEW.content_item_id;
        SELECT contract_status,allow_remote_images,allow_remote_documents
          INTO profile_status,images_allowed,documents_allowed
          FROM supplier_content_profiles WHERE supplier_code=supplier;
        IF profile_status<>'verified' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='ALSO asset cannot be approved without a verified content contract';
        END IF;
        IF NEW.asset_type='image' AND images_allowed<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Remote image use is not approved for this content profile';
        END IF;
        IF NEW.asset_type<>'image' AND documents_allowed<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Remote document use is not approved for this content profile';
        END IF;
    END IF;
END//

DELIMITER ;
