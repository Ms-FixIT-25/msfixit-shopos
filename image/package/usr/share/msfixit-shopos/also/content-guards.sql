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
    DECLARE profile_status VARCHAR(24);
    DECLARE profile_package VARCHAR(24);
    DECLARE text_allowed TINYINT;
    IF BINARY NEW.review_status=BINARY 'approved'
       AND BINARY OLD.review_status<>BINARY 'approved' THEN
        SELECT contract_status,content_package,allow_text_import
          INTO profile_status,profile_package,text_allowed
          FROM supplier_content_profiles
         WHERE BINARY supplier_code=BINARY NEW.supplier_code;
        IF BINARY profile_status<>BINARY 'verified'
           OR BINARY profile_package=BINARY 'none'
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
    DECLARE supplier VARCHAR(64);
    DECLARE profile_status VARCHAR(24);
    DECLARE images_allowed TINYINT;
    DECLARE documents_allowed TINYINT;
    IF BINARY NEW.approval_status=BINARY 'approved'
       AND BINARY OLD.approval_status<>BINARY 'approved' THEN
        SELECT i.supplier_code INTO supplier
          FROM supplier_content_items i WHERE i.id=NEW.content_item_id;
        SELECT contract_status,allow_remote_images,allow_remote_documents
          INTO profile_status,images_allowed,documents_allowed
          FROM supplier_content_profiles
         WHERE BINARY supplier_code=BINARY supplier;
        IF BINARY profile_status<>BINARY 'verified' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='ALSO asset cannot be approved without a verified content contract';
        END IF;
        IF BINARY NEW.asset_type=BINARY 'image' AND images_allowed<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Remote image use is not approved for this content profile';
        END IF;
        IF BINARY NEW.asset_type<>BINARY 'image' AND documents_allowed<>1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT='Remote document use is not approved for this content profile';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_supplier_content_change_reopens_review
BEFORE UPDATE ON supplier_content_items
FOR EACH ROW
BEGIN
    IF BINARY OLD.source_sha256<>BINARY NEW.source_sha256 THEN
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
    IF OLD.content_item_id<>NEW.content_item_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='ALSO content asset cannot be reassigned to another product';
    END IF;
    IF BINARY OLD.source_url<>BINARY NEW.source_url THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='ALSO content asset URL is immutable; insert a new asset instead';
    END IF;
END//

CREATE TRIGGER trg_supplier_content_relation_no_reassign
BEFORE UPDATE ON supplier_content_relations
FOR EACH ROW
BEGIN
    IF BINARY OLD.supplier_code<>BINARY NEW.supplier_code
       OR BINARY OLD.source_supplier_sku<>BINARY NEW.source_supplier_sku
       OR BINARY OLD.target_supplier_sku<>BINARY NEW.target_supplier_sku
       OR BINARY OLD.relation_type<>BINARY NEW.relation_type THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='ALSO content relation identity is immutable';
    END IF;
END//

DELIMITER ;
