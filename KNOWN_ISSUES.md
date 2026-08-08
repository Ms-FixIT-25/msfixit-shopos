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

### Semantic peripheral classification exists, but is not yet system- or hardware-approved
Draft #93 now classifies current USB snapshots as keyboard, mouse, HID barcode scanner, touchscreen, receipt printer, label printer, A4 printer, storage, serial adapter or unknown. It exposes capability flags and a conservative readiness state in the authenticated Hardware Manager admin view. Integrated Validation #153 and Admin Console Foundation #79 passed for this change.

Still required:
- consolidate #93 into a fresh product candidate without merging to `main` prematurely
- build a new checksummed Raspberry Pi image from that exact candidate
- rerun repeated x86_64 and ARM64 QEMU system validation on that exact image
- add persistent connect/disconnect history and privacy-safe stable device identity
- physically validate representative devices
- keep safe user-facing names and avoid unnecessary IP/MAC/customer identity collection

### Barcode scanners are not yet end-to-end proven
Most POS scanners operate as USB HID keyboards. Draft #93 can classify a scanner and show `barcode-input`, but production acceptance must prove actual barcode entry, not only USB discovery/classification.

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
Draft #93 can distinguish common printer roles and the Hardware Manager can see CUPS queues, but it deliberately does not claim a USB printer is ready merely because some CUPS queue exists. Exact device-to-queue mapping and real output remain unproven.

Required:
- discover local USB/network-capable printers without unsafe probing
- show driver/IPP capability status
- guided queue creation
- exact device-to-queue association
- test page/test receipt
- safe default-printer assignment and reversal

### Keyboard/mouse/touch input needs physical acceptance
The image carries libinput support and kiosk input access; Draft #93 classifies these device types and reports software readiness, but real hardware must prove:
- keyboard typing, Enter, Backspace and layout
- mouse movement, left/right click and wheel
- hotplug
- reconnect after boot
- touch input where advertised

### Hotplug inventory is current-state only
The admin view refreshes the Hardware Manager snapshot every 15 seconds, so newly connected/removed USB devices become visible without a reboot. Persistent connect/disconnect event history and stable privacy-safe device identity are not implemented yet.

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
