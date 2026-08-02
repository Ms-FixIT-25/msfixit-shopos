# Architecture

## Design principles

1. Minimal host operating system
2. Reproducible image builds
3. No production secrets in the repository
4. Least-privilege service accounts
5. Persistent shop data separated from the system image
6. Supplier and marketplace logic isolated from WordPress
7. Safe recovery after power, network or update failures

## Runtime overview

```text
Internet
   |
Cloudflare
   |
cloudflared
   |
Nginx
   |
PHP-FPM --- WordPress/WooCommerce
   |
MariaDB
   |
Redis

WooCommerce REST API
   |
+----------------------+----------------------+------------------+
| Catalog service      | Pricing service      | Order service    |
| Supplier connectors  | Market observations  | Supplier orders  |
+----------------------+----------------------+------------------+
```

## Bootstrap host services

- `nginx.service`
- `php8.4-fpm.service`
- `mariadb.service`
- `redis-server.service`
- `cloudflared-shopos.service`
- `shopos-firstboot.service`
- `shopos-health.timer`
- `shopos-backup.timer`
- `shopos-wp-cron.timer`

## Data separation

Version 0.1 uses the root filesystem for application state so the first flashable prototype remains simple. A later storage milestone will move persistent data below `/data` and add an explicit data partition:

```text
/data/mariadb
/data/wordpress
/data/config
/data/catalog
/data/backups
/data/logs
```

A/B system partitions, encryption and a recovery partition remain planned milestones.

## Application boundaries

### WordPress/WooCommerce

Responsible for:

- storefront
- customer accounts
- cart and checkout
- order records
- product presentation
- payment and shipping integration

Not responsible for:

- supplier selection
- market-wide repricing
- automated supplier ordering
- supplier-specific transformations
- marketplace synchronization logic

### Catalog service

Responsible for:

- supplier product imports
- EAN/GTIN and MPN matching
- stock and delivery-time synchronization
- product eligibility rules
- WooCommerce product updates

### Pricing service

Responsible for:

- landed purchase cost
- channel fees
- minimum margin
- market comparison prices
- price history
- guarded price updates

A price may never be reduced below its configured economic floor.

### Order service

Responsible for:

- validating stock before supplier submission
- selecting the preferred supplier
- preventing duplicate orders
- supplier order submission
- tracking and status synchronization
- exception queue for manual review

## Security boundaries

- Nginx listens on localhost only.
- MariaDB and Redis remain local.
- Public HTTP traffic reaches Nginx through Cloudflare Tunnel.
- SSH is limited to private IPv4 ranges by nftables.
- Root SSH login is disabled.
- Production secrets are supplied after flashing and are not stored in Git.
