DROP TRIGGER IF EXISTS trg_supplier_content_item_approval;
DROP TRIGGER IF EXISTS trg_supplier_content_asset_approval;
DROP TRIGGER IF EXISTS trg_supplier_content_change_reopens_review;
DROP TRIGGER IF EXISTS trg_supplier_content_asset_no_reassign;
DROP TRIGGER IF EXISTS trg_supplier_content_relation_no_reassign;

DELIMITER //

CREATE TRIGGER trg_supplier_content_item_approval
BEFORE UPDATE ON supplier_content_items
FOR EACH ROW
BEGIN
    DECLARE profile_status VARCHAR(24) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE profile_package VARCHAR(24) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE text_allowed TINYINT;
    IF NEW.review_status COLLATE utf8mb4_unicode_ci='approved' COLLATE utf8mb4_unicode_ci
       AND OLD.review_status COLLATE utf8mb4_unicode_ci<>'approved' COLLATE utf8mb4_unicode_ci THEN
        SELECT contract_status,content_package,allow_text_import
          INTO profile_status,profile_package,text_allowed
          FROM supplier_content_profiles
         WHERE supplier_code COLLATE utf8mb4_unicode_ci=NEW.supplier_code COLLATE utf8mb4_unicode_ci;
        IF profile_status<>'verified' COLLATE utf8mb4_unicode_ci
           OR profile_package='none' COLLATE utf8mb4_unicode_ci
           OR text_allowed<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='ALSO content cannot be approved without a verified licensed content profile';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_supplier_content_asset_approval
BEFORE UPDATE ON supplier_content_assets
FOR EACH ROW
BEGIN
    DECLARE supplier VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE profile_status VARCHAR(24) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE images_allowed TINYINT;
    DECLARE documents_allowed TINYINT;
    IF NEW.approval_status COLLATE utf8mb4_unicode_ci='approved' COLLATE utf8mb4_unicode_ci
       AND OLD.approval_status COLLATE utf8mb4_unicode_ci<>'approved' COLLATE utf8mb4_unicode_ci THEN
        SELECT i.supplier_code INTO supplier
          FROM supplier_content_items i WHERE i.id=NEW.content_item_id;
        SELECT contract_status,allow_remote_images,allow_remote_documents
          INTO profile_status,images_allowed,documents_allowed
          FROM supplier_content_profiles
         WHERE supplier_code COLLATE utf8mb4_unicode_ci=supplier COLLATE utf8mb4_unicode_ci;
        IF profile_status<>'verified' COLLATE utf8mb4_unicode_ci THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='ALSO asset cannot be approved without a verified content contract';
        END IF;
        IF NEW.asset_type COLLATE utf8mb4_unicode_ci='image' COLLATE utf8mb4_unicode_ci
           AND images_allowed<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Remote image use is not approved for this content profile';
        END IF;
        IF NEW.asset_type COLLATE utf8mb4_unicode_ci<>'image' COLLATE utf8mb4_unicode_ci
           AND documents_allowed<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Remote document use is not approved for this content profile';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_supplier_content_change_reopens_review
BEFORE UPDATE ON supplier_content_items
FOR EACH ROW
BEGIN
    IF OLD.source_sha256 <> NEW.source_sha256 THEN
        SET NEW.review_status='pending';
        SET NEW.review_reason='supplier_content_changed';
        SET NEW.reviewed_at=NULL;
        SET NEW.reviewed_by=NULL;
    END IF;
END//

CREATE TRIGGER trg_supplier_content_asset_no_reassign
BEFORE UPDATE ON supplier_content_assets
FOR EACH ROW
BEGIN
    IF OLD.content_item_id <> NEW.content_item_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='ALSO content asset cannot be reassigned to another product';
    END IF;
    IF OLD.source_url <> NEW.source_url THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='ALSO content asset URL is immutable; insert a new asset instead';
    END IF;
END//

CREATE TRIGGER trg_supplier_content_relation_no_reassign
BEFORE UPDATE ON supplier_content_relations
FOR EACH ROW
BEGIN
    IF OLD.supplier_code <> NEW.supplier_code
       OR OLD.source_supplier_sku <> NEW.source_supplier_sku
       OR OLD.target_supplier_sku <> NEW.target_supplier_sku
       OR OLD.relation_type <> NEW.relation_type THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='ALSO content relation identity is immutable';
    END IF;
END//

DELIMITER ;
