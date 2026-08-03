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
