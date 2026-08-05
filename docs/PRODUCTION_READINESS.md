# ShopOS Production Readiness

ShopOS may be called production-ready only when every mandatory gate below is evidenced by an automated result or a signed test record tied to a specific release commit and image checksum.

## Release integrity

- [x] Pull-request tests and candidate image build block merge on failure.
- [x] Production image is rebuilt from the exact final `main` commit.
- [x] Image checksum, JSON provenance and CycloneDX SBOM foundation are generated.
- [ ] GitHub Actions dependencies are pinned to reviewed immutable commit SHAs.
- [ ] Production metadata is cryptographically signed or keylessly attested.
- [ ] Root-filesystem package SBOM and vulnerability scan are attached.
- [ ] A release tag and immutable GitHub Release reference the exact artifact checksum.

## Update and recovery

- [ ] Signed A/B or transactional operating-system update mechanism.
- [ ] Automatic boot-health detection and rollback.
- [ ] Power-loss tests during download, installation, migration and first boot.
- [ ] Anti-downgrade policy for known-vulnerable releases.
- [ ] Recovery console and documented factory-reset path.
- [ ] Database migration compatibility and rollback rules.

## Backup and restore

- [ ] Encrypted local backup.
- [ ] Encrypted external or off-device backup.
- [ ] Backup retention and rotation policy.
- [ ] Automated integrity check.
- [ ] Restore test to clean replacement hardware.
- [ ] Recovery-time and recovery-point objectives documented.

## Platform security

- [ ] Threat model covering network, admin, supply chain, application packages and physical access.
- [ ] systemd sandboxing reviewed for every privileged service.
- [ ] Firewall policy and network exposure inventory.
- [ ] SSH disabled by default or key-only with explicit enablement.
- [ ] Login and public-endpoint rate limits.
- [ ] Secret rotation and diagnostic redaction tests.
- [ ] CodeQL, secret scan, dependency scan and root-filesystem CVE scan.
- [ ] Independent security review before general availability.

## Functional and hardware validation

- [ ] Boot smoke test of the exact release image.
- [ ] Raspberry Pi 4 USB-SSD cold boot, reboot and 72-hour soak.
- [ ] Raspberry Pi 5 target tests for every advertised storage mode.
- [ ] Full-disk, no-network, invalid-DNS and incorrect-clock tests.
- [ ] First-boot interruption and resume tests.
- [ ] Printer, removable-storage and supported peripheral matrix.

## Operations and support

- [ ] Structured health status for storage, temperature, services, database, backups and certificates.
- [ ] Redacted support-bundle generator.
- [ ] Incident, restore and update runbooks.
- [ ] Supported-version and end-of-life policy.
- [ ] Hardware compatibility list and known limitations.
- [ ] Pilot telemetry and failure reporting with explicit privacy controls.

## Release stages

**Development:** functional work may be incomplete and data migrations may change.

**Release candidate:** automated tests and image build pass, but physical, rollback or security gates remain open.

**Pilot:** limited, supervised installations with recoverable data and documented support contact.

**Production:** all mandatory gates above are closed for the exact released commit and artifact.
