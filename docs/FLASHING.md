# Flashing Ms. FixIT ShopOS

## Supported targets

ShopOS has separate ARM64 images for each Raspberry Pi generation. Never substitute one model's image for another.

Raspberry Pi 4 Model B:

- USB SSD or NVMe in a USB enclosure: `msfixit-shopos-rpi4-usb`
- microSD: `msfixit-shopos-rpi4-sd`

Raspberry Pi 5:

- USB SSD: `msfixit-shopos-rpi5-usb`
- microSD: `msfixit-shopos-rpi5-sd`
- native PCIe NVMe: `msfixit-shopos-rpi5-nvme`

The current GitHub Release defaults to the Raspberry Pi 4B USB-SSD image. Use wired Ethernet for the first boot.

## Raspberry Pi 4B USB-boot requirement

A Raspberry Pi 4B boots through its EEPROM bootloader. USB mass-storage boot must be supported and enabled in its boot order. Early Pi 4 bootloaders may need an update.

When unsure, first boot Raspberry Pi OS from microSD and run:

```bash
sudo rpi-eeprom-update
sudo raspi-config
```

In `raspi-config`, open **Advanced Options > Boot Order** and select an option that includes USB boot. An NVMe drive connected through a USB enclosure is treated as USB storage, not native NVMe.

## 1. Download the correct image

Open the repository's **Releases** page and choose the asset whose filename contains your exact Raspberry Pi model and storage type.

For this installation use the compressed image beginning with:

```text
msfixit-shopos-rpi4-usb.img
```

Depending on the current builder, the compression suffix may be `.zst`, `.xz` or `.gz`. The release also contains the matching `.sha256` file.

Verify the checksum before flashing.

Linux:

```bash
sha256sum -c msfixit-shopos-rpi4-usb.img.*.sha256
```

Windows PowerShell:

```powershell
Get-FileHash .\msfixit-shopos-rpi4-usb.img.zst -Algorithm SHA256
```

Use the actual downloaded suffix and compare the displayed hash with the value in the `.sha256` file.

## 2. Flash the storage device

Use Raspberry Pi Imager or balenaEtcher.

In Raspberry Pi Imager:

1. Select **Raspberry Pi 4** as the device.
2. Choose **Use custom** as the operating system.
3. Select the matching `msfixit-shopos-rpi4-*` image.
4. Select the correct USB SSD or microSD card.
5. Flash and verify it.

Do not use Raspberry Pi Imager's user-account customization. ShopOS creates and manages its own `shopadmin` account.

## 3. Optional first-boot configuration

After flashing, open the readable boot partition and create a file named `shopos.env` in its root.

```ini
SHOP_URL=https://shop.msfixit.at
SHOP_TITLE=Ms. FixIT
SHOP_ADMIN_USER=shopadmin
SHOP_ADMIN_EMAIL=office@msfixit.at
SHOP_ADMIN_PASSWORD=replace-with-a-long-random-password
OS_ADMIN_PASSWORD=replace-with-another-long-random-password
CF_TUNNEL_TOKEN=replace-with-the-cloudflare-tunnel-token
WORDPRESS_LOCALE=de_DE
WORDPRESS_VERSION=latest
```

Never commit this file or its values to GitHub.

`CF_TUNNEL_TOKEN` is optional. When it is empty, the shop remains reachable only in the private LAN. For a token-based tunnel, configure the Cloudflare public hostname to use `http://localhost:80` as its origin service.

If passwords are left empty, ShopOS generates random passwords and writes them to `SHOPOS-CREDENTIALS.txt` on the boot partition after successful provisioning.

## 4. First boot and automatic shop setup

1. Connect Ethernet.
2. Insert or connect the flashed storage device.
3. Start the Raspberry Pi 4B.
4. Allow both provisioning stages to finish.

The first stage configures MariaDB, PHP-FPM, Redis, Nginx, WordPress, WooCommerce, credentials and optional Cloudflare Tunnel access. The second stage runs `msfixit-brand-shop.service` and prepares the visible shop plus the independent article master.

The branded shop stage automatically:

- activates the WooCommerce-compatible Storefront theme
- imports the embedded Ms. FixIT artwork
- generates and assigns the header logo and site icon
- applies the navy, teal and pink color scheme
- creates the homepage, repair/services and contact pages
- creates the WooCommerce pages and main navigation
- restricts sales and delivery addresses to Austria, Germany and Switzerland
- creates a DACH shipping zone without inventing shipping prices
- initializes the `shopos_catalog` article-master database
- installs the WooCommerce bridge for immutable `MF-00000001` article numbers
- preserves supplier, old SKU, barcode, POS, marketplace and future ERP/SAP numbers as mappings
- sets Austria, euro, metric units and Europe/Vienna defaults
- leaves legal pages as unpublished drafts
- keeps search-engine indexing disabled

The first boot needs internet access because WP-CLI downloads the selected WordPress release, WooCommerce, Storefront and the Redis cache plugin. Both stages may take several minutes and retry after a temporary failure. Do not disconnect power while the activity LED and network traffic indicate ongoing setup.

Without a configured public URL, open the Raspberry Pi's LAN address in a browser:

```text
http://RASPBERRY-PI-IP/
```

SSH is allowed only from private LAN address ranges:

```bash
ssh shopadmin@RASPBERRY-PI-IP
```

## 5. What still requires a real decision

ShopOS intentionally does not guess legally or commercially sensitive settings. Before public launch, complete and test:

- payment provider and test payment
- shipping prices and return costs for AT, DE and CH
- Swiss import, customs and tax handling
- tax display for the actual business situation
- Impressum, Datenschutz, AGB and Widerruf/Rückgabe
- external backup destination and restore test
- final domain, HTTPS and indexing approval

The WordPress dashboard displays this as a go-live checklist.

## 6. Article-master administration

List current articles:

```bash
sudo msfixit-catalog list
```

Inspect one article and all mappings:

```bash
sudo msfixit-catalog show MF-00000001
```

Add supplier, barcode, POS or ERP mappings:

```bash
sudo msfixit-catalog map MF-00000001 supplier:ingram 12345678 primary
sudo msfixit-catalog map MF-00000001 gtin:ean13 4000000000000 primary
sudo msfixit-catalog map MF-00000001 pos:ready2order 9182 primary
sudo msfixit-catalog map MF-00000001 erp:sap 1000004711 primary
```

Export for another system:

```bash
sudo msfixit-catalog export-csv /data/backups/article-master.csv
```

See `docs/ARTICLE_MASTER.md` for the complete model and namespace rules.

## 7. Administration commands

Display status:

```bash
sudo msfixit-status
```

Reapply missing ShopOS branding, DACH restrictions and managed pages:

```bash
sudo msfixit-brand-shop
```

This command is idempotent and protects pages that were not created and managed by ShopOS.

Apply a changed `shopos.env` without reflashing:

```bash
sudo msfixit-apply-config
```

Run a health check:

```bash
sudo msfixit-health
```

Create a backup immediately:

```bash
sudo msfixit-backup
```

Local backups include WordPress, uploads, ShopOS configuration and the complete `shopos_catalog` database. They are stored below `/data/backups` and retained for 14 days. A separate external backup target is still required before production use.

## 8. Credentials cleanup

After saving generated credentials in a password manager, delete `SHOPOS-CREDENTIALS.txt` from the boot partition:

```bash
sudo rm -f /boot/firmware/SHOPOS-CREDENTIALS.txt /boot/SHOPOS-CREDENTIALS.txt
```
