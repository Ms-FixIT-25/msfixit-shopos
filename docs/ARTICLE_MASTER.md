# Ms. FixIT article master and integration mapping

## Purpose

ShopOS uses one permanent Ms. FixIT article number as the commercial identity of every sellable item. WooCommerce, suppliers, barcodes, a future physical shop/POS, marketplaces and an ERP such as SAP are attached through mappings instead of becoming the owner of the product identity.

```text
MF-00000001
├── WooCommerce product ID: 384
├── supplier:ingram: 12345678
├── supplier:another: ABC-77821
├── gtin:ean13: 4000000000000
├── pos:ready2order: 9182
├── channel:ebay: 33445566
└── erp:sap: 1000004711
```

Changing a supplier, webshop, POS or ERP therefore does not change the Ms. FixIT article number.

## Number format

```text
MF-00000001 … MF-99999999
```

The number is:

- unique;
- assigned sequentially;
- never reused;
- immutable after assignment;
- deliberately free of category, supplier, year, tax or location information.

Those properties can change during the life of a product and therefore do not belong in the permanent number.

Every record also has an internal UUID. The UUID is a technical database key; the `MF-…` number is the visible business article number used on invoices, labels, orders and integrations.

## Variants and bundles

Every independently sellable or stock-managed variant receives its own article number. A colour, storage size or hardware revision that has its own stock level is therefore a separate article.

A variable WooCommerce parent may have a family article number, while each purchasable variation receives its own article number and points to the parent through `parent_id`.

Bundles and service packages also receive their own article number. Their component relationships can be added later without changing the existing identifiers.

## Database boundaries

The article master is stored in the separate MariaDB database `shopos_catalog`.

Core tables:

- `catalog_products` – canonical article identity and basic status;
- `catalog_identifiers` – external numbers and mappings;
- `catalog_supplier_offers` – supplier SKU, cost, stock and lead time;
- `catalog_channel_listings` – WooCommerce, marketplaces and later POS/ERP listings;
- `catalog_sync_outbox` – ordered change events for integration adapters;
- `catalog_sequences` – protected article-number allocation.

WooCommerce is a sales channel. Its SKU is automatically set to the corresponding `MF-…` number. A previously entered WooCommerce or supplier SKU is preserved as an external mapping rather than discarded.

## Namespace convention

Mappings use a stable lowercase namespace and an external value.

Recommended namespaces:

| Purpose | Namespace example |
|---|---|
| WooCommerce database ID | `woocommerce:product_id` |
| Previous WooCommerce SKU | `woocommerce:legacy_sku` |
| Supplier article number | `supplier:ingram` |
| EAN-13 / GTIN | `gtin:ean13` |
| Internal barcode alias | `barcode:internal` |
| Physical shop/POS | `pos:ready2order` |
| SAP material number | `erp:sap` |
| Marketplace listing | `channel:ebay` |

A namespace plus external ID is globally unique. The same supplier or marketplace number cannot silently point to two Ms. FixIT articles.

## Supplier offers are not products

A supplier offer is deliberately separate from the product master. One Ms. FixIT article can have several offers with different:

- supplier SKUs;
- purchase prices;
- available quantities;
- delivery times;
- currencies;
- update timestamps.

This allows the pricing and order-routing layers to select a supplier without changing the customer-facing article identity.

## Integration outbox

Every important article or mapping change creates a row in `catalog_sync_outbox`.

Future adapters can process those events for:

- ready2order or another POS;
- SAP or another ERP;
- supplier APIs;
- accounting software;
- marketplaces;
- a local shop inventory system.

An adapter can fail and retry without losing the source change. Expansion therefore adds an adapter at the edge instead of rewriting WooCommerce or the article database.

## Administration commands

Create an article:

```bash
sudo msfixit-catalog create "Lenovo ThinkPad USB-C Dock" simple
```

Create a variation linked to a parent article:

```bash
sudo msfixit-catalog create "Notebook 16 GB / Schwarz" variation MF-00000001
```

Add supplier, barcode, POS or SAP mappings:

```bash
sudo msfixit-catalog map MF-00000001 supplier:ingram 12345678 primary
sudo msfixit-catalog map MF-00000001 gtin:ean13 4000000000000 primary
sudo msfixit-catalog map MF-00000001 pos:ready2order 9182 primary
sudo msfixit-catalog map MF-00000001 erp:sap 1000004711 primary
```

Store a supplier offer:

```bash
sudo msfixit-catalog offer MF-00000001 ingram 12345678 89.90 EUR 14 available
```

Inspect and resolve mappings:

```bash
sudo msfixit-catalog show MF-00000001
sudo msfixit-catalog resolve supplier:ingram 12345678
sudo msfixit-catalog pending 100
```

Export the master data for a POS, ERP or spreadsheet import:

```bash
sudo msfixit-catalog export-csv /data/backups/article-master.csv
```

## Barcode rule

The Ms. FixIT article number can be encoded in an internal Code 128 or QR label for a future shop without claiming that it is a globally assigned GTIN. An official EAN/GTIN remains a separate mapping under a `gtin:*` namespace.

## Backups

The normal ShopOS backup includes both the WordPress database and `shopos_catalog`, including mappings and pending integration events. An external backup destination is still required before production operation.
