# ShopOS Known Issues and Production Readiness Gaps

This document is the authoritative list of currently known product, release, hardware-validation and operational gaps for ShopOS. It must be kept aligned with the integration candidate and production-readiness GitHub issues.

## P0 — Production blockers

### Repository truth is split between `main` and the validated integration candidate
- `main` is not currently identical to the most thoroughly validated ShopOS candidate.
- The integration branch contains substantially newer product, CI, input, Hardware Manager and release-flow work.
- A production release must come from one canonical commit whose source, image artifact, SHA-256, QEMU evidence and release metadata all match.
- Do not merge blindly; first reconcile the single `main`-only commit with the integration branch and rerun the complete release gate.

### Signed transactional update and rollback are not production-proven
Tracked by #41.
- A/B update path must be signed, transactional and recover automatically.
- Power interruption must be tested during download, write, slot switch and first boot.
- Anti-downgrade and migration contracts must be proven.

### Backup and bare-metal restore are not production-proven
Tracked by #42.
- Backups must be encrypted and integrity-checked.
- Restore must succeed onto clean replacement hardware.
- WordPress, MariaDB, catalog, ShopOS data and representative transactions must survive restore.

### Runtime/security hardening is incomplete
Tracked by #43.
- Complete service/port inventory.
- Review all systemd units and capabilities.
- Harden SSH, sessions, rate limits, secrets and log redaction.
- Add negative tests that prove a compromised web process cannot invoke unintended privileged actions.

### Release provenance/SBOM/vulnerability gates are incomplete
Tracked by #44.
- Pin third-party GitHub Actions to immutable commits where feasible.
- Generate complete RootFS SBOM.
- Add CVE, secret and code security gates.
- Publish independently verifiable provenance/signatures binding source commit, image and SBOM.

### Physical Raspberry Pi validation is incomplete
Tracked by #45.
- Raspberry Pi 4 USB SSD reference hardware.
- Raspberry Pi 5 SD/USB/NVMe for every advertised target.
- 72-hour soak.
- Power-loss, full-disk, bad-clock, DNS/network-loss and storage-failure tests.
- Peripheral matrix and pilot deployment.

## P1 — Product functionality gaps

### Peripheral detection is generic, not semantic
Current Hardware Manager enumerates USB identity and CUPS queues but does not reliably classify every device as keyboard, mouse, HID barcode scanner, touchscreen, receipt printer, label printer, storage or other peripheral.

Required:
- semantic peripheral model
- stable device IDs derived from non-secret local hardware metadata
- hotplug state
- capability flags
- safe user-facing names
- no collection of unnecessary IP/MAC/customer identity data

### Barcode scanners are not yet end-to-end proven
Most POS scanners operate as USB HID keyboards, but production acceptance must prove actual barcode entry, not only USB discovery.

Required physical acceptance:
- EAN-8
- EAN-13
- Code 128
- QR where supported by the physical scanner
- fast repeated scans without lost characters
- scanner suffix Enter/Tab
- keyboard-layout correctness
- unplug/replug without reboot
- scanner attached before boot

### Printer plug-and-play is incomplete
Current CUPS detection proves configured queues, not full printer onboarding.

Required:
- discover local USB/network-capable printers without unsafe probing
- classify receipt/A4/label/other printer role
- show driver/IPP capability status
- guided queue creation
- test page/test receipt
- safe default-printer assignment and reversal

### Keyboard/mouse/touch input needs physical acceptance
The image carries libinput support and kiosk input access, but real hardware must prove:
- keyboard typing, Enter, Backspace and layout
- mouse movement, left/right click and wheel
- hotplug
- reconnect after boot
- touch input where advertised

### Thermal emergency shutdown remains intentionally disabled pending physical proof
The Hardware Manager may warn and classify emergency temperatures, but automatic shutdown must remain disabled until real hardware tests prove thresholds, hysteresis, persistence and clean shutdown behavior.

## P2 — Release and operability improvements

### Production-readiness evidence should be machine-readable
For every release candidate record:
- source SHA
- image SHA-256
- workflow run ID
- QEMU x86_64 repetitions
- QEMU ARM64 repetitions
- physical hardware results
- known limitations
- approval state

### Supportability needs a validated diagnostic workflow
- redact secrets and customer data
- collect service state, temperature, storage health, relevant logs and peripheral inventory
- export a bounded diagnostic bundle
- document operator recovery steps

### Pilot evidence is still required
Before ShopOS 1.0 production approval, operate a controlled small-device pilot and document incidents, recovery and known limits.

## Status rules

Use these states consistently:
- IMPLEMENTED — code exists
- CI-TESTED — static/unit/contract tests pass
- QEMU-TESTED — exact checksummed image boots and passes system tests
- PHYSICAL-TESTED — exact checksummed image passes on real supported hardware
- PILOT-TESTED — controlled field pilot completed
- PRODUCTION-APPROVED — all mandatory gates passed

No feature may be described as production-proven solely because it is implemented or passes QEMU.
