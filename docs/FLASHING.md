# Flashing Ms. FixIT ShopOS

## Supported target

The initial image targets **Raspberry Pi 5 (ARM64)**. Separate build configurations exist for:

- USB SSD (`usb`, default build)
- microSD (`sd`)
- NVMe (`nvme`)

Use wired Ethernet for the first boot.

## 1. Download the image

Open the repository's **Actions** tab, select **Build ShopOS image**, open the successful run and download the `msfixit-shopos-rpi5-*` artifact.

The artifact contains:

- the compressed flash image (`.img.xz`, `.img.zst`, `.img.gz` or `.img`)
- a matching SHA-256 checksum file

Verify the checksum before flashing.

Linux:

```bash
sha256sum -c msfixit-shopos-*.sha256
```

Windows PowerShell:

```powershell
Get-FileHash .\msfixit-shopos-*.img.xz -Algorithm SHA256
```

Compare the displayed hash with the value in the `.sha256` file.

## 2. Flash the storage device

Use Raspberry Pi Imager or balenaEtcher.

In Raspberry Pi Imager:

1. Select the Raspberry Pi 5.
2. Choose **Use custom** as the operating system.
3. Select the ShopOS image.
4. Select the correct SSD, SD card or NVMe device.
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

## 4. First boot

1. Connect Ethernet.
2. Insert or connect the flashed storage device.
3. Start the Raspberry Pi.
4. Allow the first-boot provisioning to finish.

The first boot needs internet access because WP-CLI downloads the selected WordPress release, WooCommerce and the Redis cache plugin. Provisioning can take several minutes and automatically retries after a temporary failure.

Without a configured public URL, open the Raspberry Pi's LAN address in a browser:

```text
http://RASPBERRY-PI-IP/
```

SSH is allowed only from private LAN address ranges:

```bash
ssh shopadmin@RASPBERRY-PI-IP
```

## 5. Administration commands

Display status:

```bash
sudo msfixit-status
```

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

Local backups are stored below `/data/backups` and retained for 14 days. A separate external backup target is still required before production use.

## 6. Credentials cleanup

After saving generated credentials in a password manager, delete `SHOPOS-CREDENTIALS.txt` from the boot partition:

```bash
sudo rm -f /boot/firmware/SHOPOS-CREDENTIALS.txt /boot/SHOPOS-CREDENTIALS.txt
```
