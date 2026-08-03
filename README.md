# Ms. FixIT ShopOS

A minimal, reproducible Raspberry Pi appliance operating system for the Ms. FixIT WooCommerce shop.

## Current status

ShopOS is structured as a **flash-image prototype**. The repository contains:

- Raspberry Pi 4 Model B targets for USB SSD and microSD
- Raspberry Pi 5 targets for USB SSD, microSD and native NVMe
- a native Nginx, PHP-FPM, MariaDB and Redis web stack
- automated WordPress and WooCommerce first-boot provisioning
- automatic Ms. FixIT branding with embedded logo, colors and site icon
- automatic Storefront theme, homepage, shop pages and main-menu setup
- initial sales and shipping restriction to Austria, Germany and Switzerland
- separate shipping zones for Austria, Germany and Switzerland
- an independent article master with immutable `MF-00000001` numbers
- generic mappings for suppliers, GTIN/EAN, WooCommerce, POS, marketplaces and ERP/SAP
- immutable invoice, credit-note and delivery-note snapshots
- payment allocation, open items and guarded reminder levels
- ProSaldo PDF/CSV handoff packages with SHA-256 manifests
- shipment, package, customs, tracking and label records
- CUPS-based A4 and A6 print queues without an additional default print daemon
- carrier account boundaries for Austrian Post, DPD AT, GLS AT, UPS and DHL DE
- optional token-based Cloudflare Tunnel startup
- LAN-restricted SSH and HTTP firewall rules
- automatic health checks and daily local backups
- GitHub Actions image building with downloadable checksums and releases

The default and release target is currently the **Raspberry Pi 4 Model B with USB SSD**. Every generated filename contains the hardware target so Pi 4 and Pi 5 images cannot be confused.

The image still needs validation on the intended Raspberry Pi, storage and printers before production use.

## Automatic shop setup

After the operating-system first boot has completed, `msfixit-brand-shop.service` automatically:

- installs and activates WooCommerce and Storefront idempotently
- imports the embedded Ms. FixIT artwork into the media library
- generates a header logo and square site icon
- applies the navy, teal and pink brand colors
- brands the public storefront and WordPress login screen
- creates a homepage, repair/services page and contact page
- creates WooCommerce pages and the primary navigation menu
- restricts sales and delivery addresses to AT, DE and CH
- creates separate AT, DE and CH shipping zones without inventing shipping prices
- initializes the independent Ms. FixIT article master
- installs the WooCommerce bridge that assigns permanent `MF-…` SKUs
- initializes the independent Office and Fulfillment database
- installs WooCommerce hooks for orders, payments, refunds and delivery notes
- starts lightweight systemd timers for Office events, overdue invoices and print jobs
- creates unpublished placeholders for Impressum, Datenschutz, AGB and Widerruf/Rückgabe
- keeps search-engine indexing disabled until the shop is deliberately approved

Existing user-created pages are detected and protected from automatic replacement. Payment providers, shipping rates, taxes, Swiss customs handling, carrier credentials and legal texts are intentionally not invented by the appliance.

## Article identity and expansion

WooCommerce is treated as one sales channel, not as the owner of product identity. Every product and every independently sellable variation receives a permanent number such as:

```text
MF-00000001
```

Supplier article numbers, WooCommerce IDs, EAN/GTIN, a future ready2order or other POS ID, marketplace listing IDs and a future SAP material number are stored as mappings to the same Ms. FixIT article.

See [`docs/ARTICLE_MASTER.md`](docs/ARTICLE_MASTER.md).

## Office and Fulfillment

WooCommerce writes compact events; the Office worker handles documents outside checkout.

```text
WooCommerce order
      |
      v
Office outbox
      +--> invoice / credit note / delivery note
      +--> payment and open item
      +--> payment reminder / approved dunning
      +--> ProSaldo handoff ZIP
      +--> shipment / carrier label / tracking
      +--> CUPS print queue
```

Final commercial documents receive protected yearly numbers, are rendered as PDFs, hashed and become immutable. Corrections use new documents instead of editing final invoices.

ShopOS does not claim a nonexistent ProSaldo shop API. It creates a controlled handoff containing PDFs, control CSVs, contact/product CSVs and a hash manifest for manual upload and booking.

Carrier API accounts begin disabled. Labels can already be archived and printed through the common pipeline; production calls to Austrian Post, DPD AT, GLS AT or UPS require the actual business contract, API credentials and assigned product codes.

See:

- [`docs/OFFICE_FULFILLMENT.md`](docs/OFFICE_FULFILLMENT.md)
- [`docs/CARRIER_INTEGRATION.md`](docs/CARRIER_INTEGRATION.md)

## Design goals

- Run only services required for the shop appliance
- Avoid Docker and a desktop environment on the production device
- Keep supplier, pricing, office and carrier automation outside checkout
- Use Cloudflare Tunnel without exposing inbound router ports
- Store changing shop and document data under `/data`
- Support repeatable image builds and replacement of the system image
- Never store production secrets in Git

## Quick start

Build the Raspberry Pi 4B USB-SSD image locally:

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

Before the first boot, an optional `shopos.env` file can be placed on the boot partition to provide the shop URL, administrator passwords and Cloudflare Tunnel token. Without it, ShopOS generates credentials and remains available only in the local network.

For Raspberry Pi 4B USB boot, the bootloader EEPROM must support and permit USB mass-storage boot. An NVMe drive connected through a USB enclosure uses the `rpi4-usb` image, not the Pi 5 NVMe image.

See:

- [`docs/FLASHING.md`](docs/FLASHING.md) for flashing and first boot
- [`docs/BUILDING.md`](docs/BUILDING.md) for local and CI builds
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for system boundaries
- [`docs/ARTICLE_MASTER.md`](docs/ARTICLE_MASTER.md) for article numbers and integrations
- [`docs/OFFICE_FULFILLMENT.md`](docs/OFFICE_FULFILLMENT.md) for invoices, reminders and ProSaldo
- [`docs/CARRIER_INTEGRATION.md`](docs/CARRIER_INTEGRATION.md) for carrier and printer onboarding

## Runtime services

```text
Cloudflare Tunnel (optional)
            |
          Nginx
            |
         PHP-FPM
            |
WordPress + WooCommerce
      |             |
   MariaDB        Redis
      |
      +--> article master
      +--> Office/Fulfillment database
             +--> document worker timer
             +--> daily dunning timer
             +--> print queue timer
```

No carrier adapter or printer server runs merely because it is present in the image.

## Administration

```bash
sudo msfixit-status
sudo msfixit-brand-shop
sudo msfixit-catalog list
sudo msfixit-office status
sudo msfixit-office dunning-run --dry-run
sudo msfixit-office carrier-list
sudo msfixit-office prosaldo-export 2026-08-01 2026-08-31
sudo msfixit-apply-config
sudo msfixit-health
sudo msfixit-backup
```

## Planned next components

- production Austrian Post adapter after contract/API onboarding
- DPD AT, GLS AT and UPS carrier adapters
- supplier API connectors feeding `catalog_supplier_offers`
- guarded pricing engine and supplier order routing
- ready2order or other POS adapter
- SAP/ERP adapter
- marketplace connectors
- external encrypted backup target
- A/B operating-system updates
