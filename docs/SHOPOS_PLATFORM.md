# ShopOS Platform Architecture

## Product model

ShopOS is split into a stable core and separately installable applications.

### ShopOS Core

The core owns only platform responsibilities:

- boot and first-run experience
- local administration GUI
- identity, authentication and authorization
- licensing and entitlement verification
- application discovery, validation, installation and removal
- updates, rollback, backup and restore orchestration
- hardware, network and notification services
- audit, health and support diagnostics

Applications must not replace or patch core files. They integrate through versioned manifests and declared capabilities.

### ShopOS Apps

Business functions are applications, for example Commerce, Repair Center, POS, ERP, Marketplace, AI Assistant and Cloud Services.

Each application is delivered as a signed package with a manifest. The manifest declares its identifier, version, compatible core API, edition, capabilities, services and UI entry points.

## Editions

- **Community:** usable base appliance, one local system, manual administration and standard backup/update functions.
- **Professional:** commercial automation, supplier and marketplace integrations, advanced backup, business analytics, multiple users and support functions.
- **Enterprise:** multi-site management, high availability, centralized policy, directory integration and custom support.

Community remains useful. Paid editions unlock time-saving, revenue-producing and operational-risk-reducing capabilities rather than disabling the basic appliance.

## Licensing boundary

ShopOS verifies digitally signed license documents. The image contains only the public verification key. Private signing keys and internal developer entitlements are never committed, embedded in images or shipped to customers.

A license document may contain:

- license identifier
- customer identifier
- edition
- explicit entitlements
- issue and optional expiry dates
- permitted installation count
- optional hardware binding policy
- detached digital signature

The internal developer entitlement follows the same verification path as customer licenses. There is no hard-coded universal bypass or plaintext master key in the product.

## Application manifest v1

```json
{
  "schema": 1,
  "id": "at.msfixit.shopos.example",
  "name": "Example App",
  "version": "1.0.0",
  "core_api": ">=1.0 <2.0",
  "edition": "professional",
  "entitlements": ["example.use"],
  "capabilities": ["navigation", "background-job"],
  "entrypoints": {
    "admin": "/apps/example/"
  }
}
```

Unknown fields are rejected in schema v1 unless explicitly documented. Identifiers are immutable and globally unique. Packages may not request unrestricted shell execution.

## Security rules

- fail closed when a license or signature cannot be validated
- never execute package lifecycle scripts before signature and manifest validation
- deny undeclared capabilities
- expose privileged operations only through narrow core-owned helpers
- record installation, removal, activation and privileged actions in the audit log
- preserve application data on failed upgrades and support transactional rollback
- do not send licensing telemetry unless the administrator explicitly enables it

## Initial implementation milestones

1. manifest parser and validator
2. entitlement verifier with signed test fixtures
3. read-only application catalog in the admin GUI
4. transactional local package installation
5. signed repository metadata and update channel
6. commercial activation and license transfer workflow
7. external developer SDK after the core API stabilizes
