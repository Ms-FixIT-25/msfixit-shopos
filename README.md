# Ms. FixIT ShopOS

A minimal, reproducible Raspberry Pi appliance operating system for the Ms. FixIT WooCommerce shop.

## Current status

ShopOS is a **flash-image prototype**. Version 0.6 defaults to a deliberately small Austrian pop-up pilot and contains:

- Raspberry Pi 4 Model B targets for USB SSD and microSD
- Raspberry Pi 5 targets for USB SSD, microSD and native NVMe
- Nginx, PHP-FPM, MariaDB and Redis without Docker or a desktop
- automated WordPress, WooCommerce and Ms. FixIT branding
- Austria-only sales and shipping while pilot mode is enabled
- a maximum of 30 manually approved pilot products
- guarded ALSO Austria SFTP price-list staging
- optional licensed 1WorldSync field intake without default image caching
- no webshop scraping, no automatic publication and no automatic supplier order
- an independent article master with immutable `MF-00000001` numbers
- mappings for suppliers, GTIN/EAN, WooCommerce, POS, marketplaces and ERP/SAP
- Austrian/DACH market, legal-text, product-safety, EPR, tax and retention controls
- immutable invoice, credit-note and delivery-note snapshots
- payment allocation, open items and guarded reminder levels
- ProSaldo PDF/CSV handoff packages with SHA-256 manifests
- shipment, package, customs, tracking and label records
- CUPS-based A4 and A6 print queues
- carrier boundaries for Austrian Post, DPD AT, GLS AT, UPS and DHL DE
- optional token-based Cloudflare Tunnel
- automatic health checks and local backups
- GitHub Actions image builds with checksums and releases

The default release target is the **Raspberry Pi 4 Model B with USB SSD**. The image still requires first-boot validation on the intended Raspberry Pi, storage and printers before production use.

## Austria-only pop-up pilot

The safe defaults are:

```text
market                    Austria only
supplier                  ALSO Austria
approved product limit    30
product selection         manual
sale-price approval       manual
WooCommerce publication   manual
supplier-order release    manual
automatic supplier order  disabled
Germany / Switzerland     blocked
```

The complete DACH structures remain installed for future expansion, but Germany and Switzerland are not offered at checkout while `AT_PILOT_ENABLED=yes`.

## ALSO Austria connector

The first connector uses the official account-specific ALSO SFTP price list. It can stage supplier SKU, manufacturer, manufacturer part number, EAN, title, descriptions, category, purchase price, availability, lead time and licensed content links.

```text
ALSO feed
   ↓
validated staging and quarantine
   ↓
manual selection and explicit sale price
   ↓
permanent MF article number
   ↓
hidden WooCommerce draft
   ↓
product-safety and market approval
   ↓
manual publication in Austria
```

Existing linked products may receive updated supplier-offer price, stock and lead-time snapshots. The public sale price is never changed automatically.

ALSO XML price/availability, order submission, order response and direct-to-customer delivery remain disabled until ALSO supplies the reseller account's official XML guideline, endpoint, credentials and test environment.

See [`docs/AT_PILOT_ALSO.md`](docs/AT_PILOT_ALSO.md).

## Automatic shop setup

After first boot, `msfixit-brand-shop.service`:

- installs and activates WooCommerce and Storefront idempotently
- imports the embedded Ms. FixIT artwork and applies the brand colors
- creates the homepage, service, contact and WooCommerce pages
- enables the Austria-only pilot shipping zone
- initializes the article master, Office/Fulfillment and compliance databases
- initializes the ALSO staging tables and a disabled-by-default SFTP connector
- installs WooCommerce bridges and the Austria pilot guard
- starts lightweight timers for Office, compliance, printing and ALSO intake
- creates legal-page placeholders without pretending they are reviewed texts
- keeps public indexing disabled until deliberate approval

Existing user-created pages are protected from automatic replacement. Payment providers, shipping rates, tax decisions, carrier credentials, legal texts and supplier credentials are never invented by the appliance.

## Article identity and expansion

WooCommerce and ALSO are integrations, not owners of product identity. Every product and independently sellable variation receives a permanent number such as:

```text
MF-00000001
```

ALSO SKUs, manufacturer numbers, EAN/GTIN, WooCommerce IDs, future POS IDs, marketplace IDs and SAP material numbers map to the same Ms. FixIT article.

See [`docs/ARTICLE_MASTER.md`](docs/ARTICLE_MASTER.md).

## Office, compliance and fulfillment

WooCommerce writes compact events; workers handle documents and integrations outside checkout.

```text
WooCommerce order
      |
      +--> Office outbox
      |      +--> invoice / credit note / delivery note
      |      +--> payment and open item
      |      +--> guarded reminder
      |      +--> ProSaldo handoff
      |      +--> shipment / label / print
      |
      +--> compliance evidence
      |
      +--> manual ALSO purchase release
```

Final commercial documents receive protected yearly numbers, PDFs and hashes and become immutable. Unsupported DACH tax and structured-e-invoice cases remain blocked instead of producing incomplete documents.

See:

- [`docs/DACH_COMPLIANCE.md`](docs/DACH_COMPLIANCE.md)
- [`docs/OFFICE_FULFILLMENT.md`](docs/OFFICE_FULFILLMENT.md)
- [`docs/CARRIER_INTEGRATION.md`](docs/CARRIER_INTEGRATION.md)

## Quick start

```bash
make check
make image-rpi4-usb
```

Other targets:

```bash
make image-rpi4-sd
make image-rpi5-usb
make image-rpi5-sd
make image-rpi5-nvme
```

Before first boot, an optional `shopos.env` on the boot partition can provide the shop URL, administrator passwords and Cloudflare Tunnel token. Without it, ShopOS generates credentials and remains local.

For Raspberry Pi 4B USB boot, the EEPROM bootloader must permit USB mass-storage boot. An NVMe drive in a USB enclosure uses the `rpi4-usb` image.

## Administration

```bash
sudo msfixit-status
sudo msfixit-also status
sudo msfixit-also import-file /path/to/also.csv dry-run
sudo msfixit-also list new 100
sudo msfixit-also approve ALSO-SKU 149.90 shopadmin
sudo msfixit-also release-order WOOCOMMERCE_ORDER_ID PURCHASE_TOTAL shopadmin
sudo msfixit-catalog list
sudo msfixit-office status
sudo msfixit-compliance status
sudo msfixit-health
sudo msfixit-backup
```

## Design boundaries

- production credentials remain outside Git
- the ALSO reseller webshop is not scraped
- supplier content is used only within the licensed feed rights
- images are not cached locally by default
- pilot products are never auto-published
- pilot orders are never sent to ALSO automatically
- compliance and tax decisions fail closed
- technical controls do not replace professional legal or tax review

## Planned expansion

- account-tested ALSO XML price and availability adapter
- account-tested XML order, order-response, delivery and invoice adapters
- ALSO direct-to-customer dispatch after test approval
- Austrian Post production adapter
- additional wholesalers through the same staging interface
- guarded pricing and supplier-routing rules
- ready2order or another POS adapter
- SAP/ERP and marketplace adapters
- external encrypted backups
- A/B operating-system updates
