# Ms. FixIT ShopOS

A minimal, reproducible Raspberry Pi appliance operating system for the Ms. FixIT WooCommerce shop.

## Current status

ShopOS is structured as a **flash-image prototype**. The repository contains:

- Raspberry Pi 4 Model B targets for USB SSD and microSD
- Raspberry Pi 5 targets for USB SSD, microSD and native NVMe
- a native Nginx, PHP-FPM, MariaDB and Redis web stack
- automated WordPress and WooCommerce first-boot provisioning
- optional token-based Cloudflare Tunnel startup
- LAN-restricted SSH and HTTP firewall rules
- automatic health checks and daily local backups
- GitHub Actions image building with downloadable checksums and releases

The default and release target is currently the **Raspberry Pi 4 Model B with USB SSD**. Every generated filename contains the hardware target so Pi 4 and Pi 5 images cannot be confused.

The first image still needs validation on the intended Raspberry Pi and storage hardware before production use.

## Design goals

- Run only services required for the shop appliance
- Avoid Docker and a desktop environment on the production device
- Keep supplier, pricing and order automation outside WordPress
- Use Cloudflare Tunnel without exposing inbound router ports
- Store changing shop data under `/data`
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

Or download the correctly named image from GitHub Releases.

Before the first boot, an optional `shopos.env` file can be placed on the boot partition to provide the shop URL, administrator passwords and Cloudflare Tunnel token. Without it, ShopOS generates credentials and remains available only in the local network.

For Raspberry Pi 4B USB boot, the bootloader EEPROM must support and permit USB mass-storage boot. An NVMe drive connected through a USB enclosure uses the `rpi4-usb` image, not the Pi 5 NVMe image.

See:

- [`docs/FLASHING.md`](docs/FLASHING.md) for flashing and first boot
- [`docs/BUILDING.md`](docs/BUILDING.md) for local and CI builds
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for system boundaries

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
```

Additional services:

- `msfixit-firstboot.service`
- `msfixit-cloudflared.service`
- `msfixit-health.timer`
- `msfixit-backup.timer`

## Administration

```bash
sudo msfixit-status
sudo msfixit-apply-config
sudo msfixit-health
sudo msfixit-backup
```

## Planned next components

- supplier catalog connectors
- guarded pricing engine
- automatic supplier order routing
- marketplace connectors
- external encrypted backup target
- A/B operating-system updates
