# ShopOS Admin Console – Foundation

## Status

Initial planning and implementation branch. This work starts only after repeated green QEMU and ARM64 system validation.

## Goals

- secure local administration interface for ShopOS
- system health overview for Nginx, PHP-FPM, MariaDB, Redis and WordPress
- storage, temperature, uptime and ShopOS version display
- controlled actions for cache, backups, restore preparation and updates
- audit logging for administrative actions
- no direct exposure to the public internet by default

## Security baseline

- bind to localhost or the trusted LAN only
- authenticate through a dedicated administrator account
- CSRF protection for all state-changing actions
- secure session cookies and session rotation after login
- least-privilege helper commands instead of unrestricted shell access
- allowlisted systemd operations only
- never expose secrets, database passwords or raw credential files
- record actor, timestamp, action and result in an audit log

## Proposed architecture

1. A small PHP application served through the existing Nginx and PHP-FPM stack.
2. Read-only status collection from systemd, `/proc`, thermal sensors and ShopOS metadata.
3. Privileged operations delegated to narrowly scoped root-owned helper scripts.
4. Explicit sudoers allowlist for those helpers only.
5. JSON endpoints used by the local dashboard, with server-side authorization on every request.

## Phase 1

- authenticated login and logout
- dashboard shell
- service-state API
- ShopOS version, uptime, storage and temperature
- security regression tests
- QEMU and ARM64 smoke-test integration

## Phase 2

- backup creation and status
- cache flush
- controlled service restart
- log viewer with bounded output and secret filtering

## Phase 3

- restore workflow with confirmation and validation
- update readiness and update execution
- maintenance mode
- extended audit and recovery tests

## Acceptance criteria for Phase 1

- unauthenticated access is denied
- successful login rotates the session identifier
- state-changing requests require a valid CSRF token
- dashboard reports all core services accurately
- no secret values are rendered or logged
- all new shell and PHP files pass syntax checks
- normal and ARM64 QEMU validation remain green

Nothing in this branch may be merged automatically.
