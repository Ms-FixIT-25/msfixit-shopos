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

## Planned host services

- `nginx.service`
- `php-fpm.service`
- `mariadb.service`
- `redis-server.service`
- `cloudflared.service`
- `fixit-catalog.service`
- `fixit-pricing.service`
- `fixit-orders.service`
- `fixit-health.service`
- `fixit-backup.timer`
- `fixit-sync.timer`

## Data separation

The operating system should be replaceable without losing shop data. Persistent data belongs below `/data`:

```text
/data/mariadb
/data/wordpress/uploads
/data/config
/data/catalog
/data/backups
/data/logs
```

The initial development image may use a simpler partition layout. A/B system partitions and a recovery partition are later milestones and must not block the first bootable prototype.

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

- MariaDB and Redis bind to localhost only.
- Internal services bind to localhost or a private Unix socket.
- Public HTTP traffic reaches Nginx only through Cloudflare Tunnel.
- SSH uses keys only and is restricted to the administration network.
- Every custom service runs under a dedicated unprivileged account.
- Production configuration is supplied outside Git.
