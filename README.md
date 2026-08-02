# Ms. FixIT ShopOS

A minimal, reproducible Raspberry Pi 5 appliance operating system for the Ms. FixIT WooCommerce shop.

## Current milestone: 0.1 bootstrap image

The repository now contains a build definition for a flashable ARM64 image based on Raspberry Pi's `rpi-image-gen` and Debian Trixie. The image contains only the shop web stack and operational services:

- Nginx bound to localhost
- PHP-FPM
- MariaDB
- Redis
- WordPress/WooCommerce provisioning through `shopos-setup`
- Cloudflare Tunnel client
- nftables firewall
- SSH bootstrap with either a supplied public key or a generated one-time password
- systemd health checks, WordPress cron and local backups

No production secrets are stored in Git.

## Build

Run on a native ARM64 Debian Bookworm/Trixie or 64-bit Raspberry Pi OS host:

```bash
./scripts/build-image.sh
```

The output is written to:

```text
artifacts/msfixit-shopos-rpi5.img.xz
artifacts/msfixit-shopos-rpi5.img.xz.sha256
```

The GitHub Actions workflow uses GitHub's ARM64 Ubuntu runner to produce the same artifact.

## First boot

See [`docs/FLASHING.md`](docs/FLASHING.md).

## Security model

- Nginx listens on `127.0.0.1:8080`; Cloudflare Tunnel is the public entry point.
- MariaDB and Redis remain local.
- Incoming traffic is denied by default.
- SSH is accepted only from private IPv4 address ranges.
- Root SSH login is disabled.
- WordPress's built-in file editor is disabled after setup.
- Cloudflare and database secrets live under `/etc/shopos` with root-only permissions.

## Not implemented yet

- Supplier API connectors
- Marketplace connectors
- Automatic pricing and margin rules
- External/off-device backup transport
- A/B atomic operating-system updates
- Encrypted data partition
- Production load and recovery testing

This repository is public. Never commit API keys, Cloudflare tokens, database dumps or customer data.
