# Flashing and first boot

## Build artifact

The GitHub Actions workflow `Build flashable ShopOS image` produces:

- `msfixit-shopos-rpi5.img.xz`
- `msfixit-shopos-rpi5.img.xz.sha256`

Verify the checksum before flashing:

```bash
sha256sum -c msfixit-shopos-rpi5.img.xz.sha256
```

## Flash

Use Raspberry Pi Imager and choose **Use custom**, then select the `.img.xz` file. Target an SSD or NVMe drive where possible.

The image currently targets **Raspberry Pi 5 ARM64**.

## Optional SSH key before first boot

After flashing, open the boot partition and create a file named:

```text
shopos-authorized_keys
```

Paste exactly one SSH public key into it. On first boot ShopOS installs this key for the `shopadmin` user and keeps password login locked.

Without that file, ShopOS generates a temporary password and writes it to:

```text
SHOPOS-FIRST-LOGIN.txt
```

on the boot partition. Change the password immediately at first login.

## Configure the shop

Connect from the local network:

```bash
ssh shopadmin@msfixit-shopos
sudo shopos-setup
```

The setup command creates the MariaDB database, downloads verified WordPress core files through WP-CLI, installs WooCommerce and Redis Object Cache, configures the Cloudflare Tunnel token if supplied, creates the first backup, and optionally switches SSH to key-only authentication.

The shop listens only on `127.0.0.1:8080`. It is not directly exposed to the LAN or Internet. Cloudflare Tunnel is the intended public entry point.

## Backups

Local backups are written to `/var/backups/shopos` every day. Copy them to another device. A backup stored only on the same SSD is not disaster recovery.

## Important status

Version 0.1 is a bootstrap image. It has not yet implemented A/B system updates, encrypted data partitions, supplier connectors, marketplace connectors, or automatic repricing.
