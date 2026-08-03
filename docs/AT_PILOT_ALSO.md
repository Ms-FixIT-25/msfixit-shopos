# Austria-only pop-up pilot with ALSO Austria

## Goal

ShopOS starts as a deliberately small Austrian pilot instead of opening the full DACH operation immediately.

Default limits:

- sales and shipping only within Austria;
- one supplier: `also-at`;
- at most 30 approved pilot products;
- manual product selection and sale-price approval;
- manual supplier-order release after a fresh price and stock check;
- no automatic WooCommerce publication;
- no automatic ALSO order or dropship request;
- no Germany or Switzerland checkout.

The DACH compliance and integration structures remain installed for later expansion, but only Austria is active in pilot mode.

## Official ALSO integration layers

The connector is designed around the official ALSO Austria services rather than scraping the reseller webshop.

### 1. SFTP price list – implemented pilot intake

The first connector imports an account-specific `.csv` or `.txt` price list received over SFTP.

It can stage:

- ALSO supplier SKU;
- manufacturer and manufacturer part number;
- EAN/GTIN;
- product name;
- short and marketing descriptions when licensed;
- category;
- current purchase price and currency;
- stock quantity or availability state;
- lead time;
- image and datasheet links when supplied.

Header names, delimiter and text encoding are configurable because ALSO can supply individualized price lists.

### 2. 1WorldSync content – license controlled

ALSO offers optional content feeds with descriptions, image links, datasheets and extended specifications. ShopOS stores the configured content-license level with every feed item.

Safe defaults:

```ini
ALSO_CONTENT_LICENSE=none
ALSO_ALLOW_MARKETING_TEXT=no
ALSO_ALLOW_LOCAL_IMAGE_CACHE=no
```

The pilot never downloads supplier images into WordPress automatically. Local image storage may be added only when the purchased content contract explicitly permits it. A remote image URL is stored only as internal supplier metadata until then.

### 3. XML Complete / WebServices – prepared but disabled

ALSO supports live price and availability queries, XML ordering, order responses, delivery notifications, invoice data and direct delivery to the reseller's end customer.

Those functions remain disabled in the pilot:

```ini
ALSO_XML_ENABLED=no
ALSO_XML_PRICE_AVAILABILITY_ENABLED=no
ALSO_XML_ORDER_ENABLED=no
ALSO_XML_DROPSHIP_ENABLED=no
```

They may be implemented only after ALSO activates the reseller account and supplies the account-specific XML guideline, endpoint, credentials and test environment. ShopOS does not invent message formats or production endpoints.

## Data flow

```text
ALSO SFTP feed
      ↓
validated staging record
      ↓
new / changed / quarantined review list
      ↓
manual product and sale-price approval
      ↓
permanent Ms. FixIT article number
      ↓
WooCommerce hidden draft
      ↓
product-safety, legal and tax approval
      ↓
manual publication for Austria
```

A feed import never creates a public product and never sends an order.

## Configuration

On the Raspberry Pi:

```bash
sudo nano /etc/msfixit-shopos/also.env
```

Required SFTP settings:

```ini
ALSO_ENABLED=yes
ALSO_SFTP_HOST=provided-by-also
ALSO_SFTP_PORT=22
ALSO_SFTP_USER=provided-by-also
ALSO_SFTP_REMOTE_FILE=/provided/path/price-list.csv
ALSO_SFTP_AUTH=key
ALSO_SFTP_IDENTITY_FILE=/etc/msfixit-shopos/also/id_ed25519
ALSO_SFTP_KNOWN_HOSTS=/etc/msfixit-shopos/also/known_hosts
```

The host key must be obtained through a trusted ALSO onboarding channel and pinned in `known_hosts`. Do not accept an unknown host key automatically on the production Raspberry Pi.

Password authentication is supported through a root-only password file:

```ini
ALSO_SFTP_AUTH=password
ALSO_SFTP_PASSWORD_FILE=/etc/msfixit-shopos/also/password
```

The password is read with `sshpass -f` and is not placed on the command line.

## Feed mapping

Example:

```ini
ALSO_FEED_ENCODING=UTF-8
ALSO_FEED_DELIMITER=semicolon
ALSO_FIELD_SUPPLIER_SKU=SupplierSKU
ALSO_FIELD_MANUFACTURER=Manufacturer
ALSO_FIELD_MANUFACTURER_SKU=ManufacturerSKU
ALSO_FIELD_GTIN=EAN
ALSO_FIELD_PRODUCT_NAME=ProductName
ALSO_FIELD_PURCHASE_PRICE=PurchasePrice
ALSO_FIELD_CURRENCY=Currency
ALSO_FIELD_STOCK_QUANTITY=Stock
ALSO_FIELD_STOCK_STATUS=Availability
```

Set the values to the exact column names in the activated ALSO file.

## Initial connection and import

Test only the download:

```bash
sudo msfixit-also test-connection
```

Test an already downloaded feed without writing to the database:

```bash
sudo msfixit-also import-file /path/to/feed.csv dry-run
```

Run a real local import:

```bash
sudo msfixit-also import-file /path/to/feed.csv
```

Run SFTP synchronization:

```bash
sudo msfixit-also sync
```

A systemd timer runs every six hours. When `ALSO_ENABLED=no`, it exits safely without network access.

## Review workflow

Connector status:

```bash
sudo msfixit-also status
```

New items:

```bash
sudo msfixit-also list new 100
```

Quarantined items:

```bash
sudo msfixit-also list quarantined 100
```

One item including the original supplier payload:

```bash
sudo msfixit-also show ALSO-SKU
```

Export the review list:

```bash
sudo msfixit-also export-review /data/suppliers/also/reports/review.csv
```

## Product approval

Select a product and approve an explicit Austrian sale price:

```bash
sudo msfixit-also approve ALSO-SKU 149.90 shopadmin
```

This transaction:

1. checks current feed status, price and stock;
2. enforces the 30-product pilot limit;
3. allocates a permanent `MF-…` article number;
4. maps the ALSO SKU, GTIN and manufacturer number;
5. stores the current supplier offer;
6. creates a hidden WooCommerce draft;
7. keeps product compliance at `pending`;
8. does not download an image;
9. does not publish the product.

Reject a candidate:

```bash
sudo msfixit-also reject ALSO-SKU "Not suitable for the pilot" shopadmin
```

## Price and stock updates

For linked products, imports may update only the supplier-offer snapshot:

- current purchase price;
- supplier stock;
- availability state;
- lead time;
- raw supplier payload and timestamp.

The public WooCommerce sale price is not changed automatically. Purchase-price changes at or above the configured percentage are entered into the review journal.

```ini
AT_PILOT_PRICE_CHANGE_REVIEW_PERCENT=5
```

The initial proposed-price function is disabled until its tax and margin assumptions are deliberately approved:

```ini
AT_PILOT_PRICING_APPROVED=no
```

## Order release

Every pilot order receives:

```text
supplier release status = pending_manual_review
supplier order sent      = no
```

After checking the current ALSO price and stock, record a manual purchasing release:

```bash
sudo msfixit-also release-order WOOCOMMERCE_ORDER_ID PURCHASE_TOTAL shopadmin
```

This records the release but does not transmit an XML order. Ordering remains in the ALSO webshop until the XML test integration is implemented and separately enabled.

## Expansion path

Later expansion does not replace the article master:

- ALSO XML price/availability adapter;
- XML order and order-response adapter;
- delivery-note and invoice ingestion;
- direct-to-customer dispatch request;
- automatic tracking ingestion;
- additional wholesalers through the same staging tables;
- Germany and Switzerland market activation;
- POS or ERP/SAP synchronization through the existing mapping and outbox layers.

The permanent `MF-…` number remains the product identity throughout.
