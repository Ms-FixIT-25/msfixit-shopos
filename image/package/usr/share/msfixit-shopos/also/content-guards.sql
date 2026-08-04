DROP TRIGGER IF EXISTS trg_supplier_content_change_reopens_review;
DROP TRIGGER IF EXISTS trg_supplier_content_asset_no_reassign;
DROP TRIGGER IF EXISTS trg_supplier_content_relation_no_reassign;

DELIMITER //

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
