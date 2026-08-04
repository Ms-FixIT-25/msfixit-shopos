CREATE TABLE IF NOT EXISTS partner_schema_versions (
    version_number INT UNSIGNED NOT NULL PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO partner_schema_versions (version_number) VALUES (1);

CREATE TABLE IF NOT EXISTS partner_profiles (
    partner_code VARCHAR(64) NOT NULL PRIMARY KEY,
    provider_name VARCHAR(191) NOT NULL,
    program_name VARCHAR(191) NOT NULL,
    public_label VARCHAR(191) NOT NULL,
    membership_status VARCHAR(24) NOT NULL DEFAULT 'unverified',
    valid_from DATE NULL,
    valid_until DATE NULL,
    evidence_path VARCHAR(1000) NULL,
    evidence_sha256 CHAR(64) NULL,
    evidence_checked_at TIMESTAMP NULL DEFAULT NULL,
    evidence_checked_by VARCHAR(191) NULL,
    public_claim VARCHAR(1000) NULL,
    official_profile_url VARCHAR(2000) NULL,
    public_enabled TINYINT(1) NOT NULL DEFAULT 0,
    logo_mode VARCHAR(24) NOT NULL DEFAULT 'none',
    logo_url VARCHAR(2000) NULL,
    logo_rights_verified TINYINT(1) NOT NULL DEFAULT 0,
    logo_evidence_path VARCHAR(1000) NULL,
    logo_evidence_sha256 CHAR(64) NULL,
    logo_checked_at TIMESTAMP NULL DEFAULT NULL,
    logo_checked_by VARCHAR(191) NULL,
    notes VARCHAR(2000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY ix_partner_profiles_public (public_enabled, membership_status, valid_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO partner_profiles
(partner_code, provider_name, program_name, public_label, notes)
VALUES
('fritz-business-at', 'FRITZ!', 'FRITZ! Business-Partnerprogramm Österreich', 'FRITZ! Business-Partner', 'Exact programme level and current validity require account evidence.'),
('ifixit-pro', 'iFixit', 'iFixit Pro', 'iFixit Pro Mitglied', 'Membership is not a certification. Logo use requires separate written permission.');

CREATE TABLE IF NOT EXISTS partner_profile_audit (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    partner_code VARCHAR(64) NOT NULL,
    action_name VARCHAR(64) NOT NULL,
    actor_name VARCHAR(191) NOT NULL,
    details_json JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_partner_profile_audit_partner (partner_code, created_at),
    CONSTRAINT fk_partner_profile_audit_profile
        FOREIGN KEY (partner_code) REFERENCES partner_profiles (partner_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS trg_partner_profile_identity_immutable;
DROP TRIGGER IF EXISTS trg_partner_profile_public_safety;
DROP TRIGGER IF EXISTS trg_partner_profile_logo_safety;
DROP TRIGGER IF EXISTS trg_partner_profile_no_delete;

DELIMITER //

CREATE TRIGGER trg_partner_profile_identity_immutable
BEFORE UPDATE ON partner_profiles
FOR EACH ROW
BEGIN
    IF BINARY OLD.partner_code <> BINARY NEW.partner_code
       OR BINARY OLD.provider_name <> BINARY NEW.provider_name THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='Partner profile identity is immutable';
    END IF;
END//

CREATE TRIGGER trg_partner_profile_public_safety
BEFORE UPDATE ON partner_profiles
FOR EACH ROW
BEGIN
    IF NEW.public_enabled=1 THEN
        IF BINARY NEW.membership_status <> BINARY 'verified' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Public partner claim requires verified membership';
        END IF;
        IF NEW.evidence_path IS NULL OR NEW.evidence_path=''
           OR NEW.evidence_sha256 IS NULL OR NEW.evidence_sha256='' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Public partner claim requires evidence path and checksum';
        END IF;
        IF NEW.valid_until IS NOT NULL AND NEW.valid_until < CURRENT_DATE THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Expired partner membership cannot be published';
        END IF;
        IF NEW.public_claim IS NULL OR CHAR_LENGTH(TRIM(NEW.public_claim)) < 8 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Public partner claim requires reviewed wording';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_partner_profile_logo_safety
BEFORE UPDATE ON partner_profiles
FOR EACH ROW
BEGIN
    IF BINARY NEW.logo_mode <> BINARY 'none' THEN
        IF NEW.logo_rights_verified<>1
           OR NEW.logo_url IS NULL OR NEW.logo_url=''
           OR NEW.logo_evidence_path IS NULL OR NEW.logo_evidence_path=''
           OR NEW.logo_evidence_sha256 IS NULL OR NEW.logo_evidence_sha256='' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Partner logo requires separately verified usage rights and evidence';
        END IF;
        IF NEW.logo_url NOT LIKE 'https://%' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Partner logo URL must use HTTPS';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_partner_profile_no_delete
BEFORE DELETE ON partner_profiles
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT='Partner profiles must be disabled, not deleted';
END//

DELIMITER ;
