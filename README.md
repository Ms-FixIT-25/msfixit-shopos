# Ms. FixIT ShopOS

A minimal, reproducible Raspberry Pi appliance operating system for the Ms. FixIT WooCommerce shop.

## Goals

- Run only the services required for the shop appliance
- Provide WordPress and WooCommerce as the storefront
- Keep supplier, pricing and order automation outside WordPress
- Use Cloudflare Tunnel without exposing inbound router ports
- Separate immutable system components from persistent shop data
- Support backups, health checks and safe system updates
- Never store production secrets in Git

## Project status

Early architecture and bootstrap phase. No production image is available yet.

## Planned components

- Raspberry Pi image build
- Nginx and PHP-FPM
- MariaDB and Redis
- WordPress and WooCommerce provisioning
- Catalog service
- Pricing engine
- Order router
- Supplier and marketplace connectors
- Backup and health services

See `docs/` for the architecture and implementation roadmap as the project develops.
