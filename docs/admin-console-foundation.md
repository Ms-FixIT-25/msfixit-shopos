# ShopOS Admin Console – Foundation

## Status

Phase 1 is merged and validated. Phase 2 is implemented on a separate draft branch and remains subject to CI and system validation.

## Goals

- secure local administration interface for ShopOS
- system health overview for Nginx, PHP-FPM, MariaDB, Redis and WordPress
- storage, temperature, uptime and ShopOS version display
- controlled actions for cache, backups and service restarts
- bounded, secret-filtered log viewing
- audit logging for administrative actions
- no direct exposure to the public internet by default

## Security baseline

- bind to localhost or the trusted LAN only
- authenticate through a dedicated administrator account
- CSRF protection for all state-changing actions
- secure session cookies and session rotation after login
- least-privilege helper commands instead of unrestricted shell access
- explicit sudoers allowlist for each helper invocation
- never expose secrets, database passwords or raw credential files
- record actor, timestamp, action, argument and result in an audit log
- cap log output and redact common secret assignments

## Architecture

1. A small PHP application served through the existing Nginx and PHP-FPM stack.
2. Read-only status collection from systemd, `/proc`, thermal sensors and ShopOS metadata.
3. Privileged operations delegated to the root-owned `/usr/local/sbin/msfixit-admin-action` helper.
4. Exact command and argument combinations allowlisted in `/etc/sudoers.d/msfixit-admin-console`.
5. JSON status endpoint and authenticated POST actions with server-side authorization.

## Phase 1

- authenticated login and logout
- dashboard shell
- service-state API
- ShopOS version, uptime, storage and temperature
- security regression tests
- QEMU and ARM64 smoke-test integration

## Phase 2

- backup creation under `/data/backups`
- Redis and WordPress cache flush
- controlled restart of Nginx, MariaDB, Redis and PHP-FPM
- bounded service log viewer with common secret filtering
- latest-backup status in the JSON status API
- audit records in journald and `/var/log/msfixit-shopos/admin-audit.log`

## Phase 3

- restore workflow with confirmation and validation
- update readiness and update execution
- maintenance mode
- extended audit and recovery tests

## Acceptance criteria for Phase 2

- unauthenticated requests cannot execute actions
- every action requires a valid CSRF token
- PHP accepts only allowlisted action and argument combinations
- sudoers grants no unrestricted shell or wildcard command access
- helper rejects all unknown actions and service names
- logs are limited to 200 lines and common secret assignments are redacted
- every action writes an audit result
- all shell and PHP files pass syntax checks
- normal and ARM64 QEMU validation are run once for the final relevant product image

Nothing in this branch may be merged automatically.
