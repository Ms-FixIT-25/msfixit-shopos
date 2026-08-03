DROP TRIGGER IF EXISTS trg_catalog_supplier_offer_no_reassign;
DROP TRIGGER IF EXISTS trg_catalog_channel_listing_no_reassign;

DELIMITER //

CREATE TRIGGER trg_catalog_supplier_offer_no_reassign
BEFORE UPDATE ON catalog_supplier_offers
FOR EACH ROW
BEGIN
    IF OLD.product_id <> NEW.product_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Supplier offers cannot be reassigned to another article';
    END IF;
END//

CREATE TRIGGER trg_catalog_channel_listing_no_reassign
BEFORE UPDATE ON catalog_channel_listings
FOR EACH ROW
BEGIN
    IF OLD.product_id <> NEW.product_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Channel listings cannot be reassigned to another article';
    END IF;
END//

DELIMITER ;
