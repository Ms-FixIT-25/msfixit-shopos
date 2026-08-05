# ShopOS Security Policy

## Supported status

ShopOS is currently a controlled pilot and release-candidate project. It is not yet approved for unattended production deployment. Supported versions and security-fix windows will be defined before the first production release.

## Reporting a vulnerability

Do not publish exploitable details in a public issue. Report suspected vulnerabilities privately to the repository owner through GitHub's private vulnerability reporting feature when enabled. Include the affected commit or version, reproduction steps, expected impact and any proposed mitigation.

## Security principles

- fail closed when identity, license, entitlement, package integrity or configuration cannot be verified;
- never embed private signing keys or universal bypass credentials;
- minimize GitHub Actions and runtime privileges;
- sign or attest release metadata before production distribution;
- keep customer secrets and personal data out of logs, diagnostics and public artifacts;
- require tested backup and recovery before production approval;
- require a verified rollback path for operating-system updates.

## Release policy

A production release must be built from the exact commit on `main`, pass the complete test suite, produce a verified image checksum, provenance record and machine-readable SBOM, and complete the hardware and recovery gates documented in `docs/PRODUCTION_READINESS.md`.
