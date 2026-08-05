# ShopOS Operations Runbook

## Before deployment

Record the release commit, image filename, SHA-256 checksum, target hardware, storage serial number and backup destination. Confirm that the artifact is a production build from the exact `main` commit and not a candidate artifact.

## First boot

Verify power stability, storage health, network configuration, system time and the final OOBE status. Do not expose the public shop or service-request intake until legal, privacy, payment, shipping and backup checks are complete.

## Daily health

Review failed systemd units, free disk space and inodes, CPU temperature and throttling, MariaDB/Redis/Nginx/PHP status, backup age, certificate expiry, print queues and pending commercial integration jobs.

## Incident priorities

1. Protect customer and commercial data.
2. Stop unsafe publication, order transmission or privileged actions.
3. Preserve logs and hashes without exposing secrets.
4. Restore service from a verified image and tested backup.
5. Record root cause, affected versions and corrective action.

## Recovery rule

Never perform an irreversible repair on the only copy of customer data. Clone or back up the affected storage first where technically possible. A restore is complete only after application health, database consistency, authentication and a representative business workflow have been verified.

## Escalation blockers

Do not continue automated rollout when image identity is unclear, checksums fail, backups are stale, database migrations are incomplete, storage reports errors, system time is invalid or the device repeatedly falls back during boot.
