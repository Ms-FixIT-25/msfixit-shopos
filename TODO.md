# ShopOS Production TODO

This is the prioritized execution list for moving ShopOS from release-candidate quality to production software.

## P0 — Do before any production release

- [ ] Reconcile `main` and `integration/shopos-master-consolidation` into one canonical candidate without blind merge.
- [ ] Rerun full static, integrated, build, checksum, x86_64-QEMU and ARM64-QEMU gates on that exact canonical commit.
- [ ] Finish #41 signed transactional A/B update, automatic rollback, anti-downgrade and power-loss validation.
- [ ] Finish #42 encrypted backup plus bare-metal restore to clean replacement hardware.
- [ ] Finish #43 system-wide service/network/admin security hardening and negative tests.
- [ ] Finish #44 SBOM, provenance/signature, CVE, secret and code-security release gates.
- [ ] Finish #45 physical Raspberry Pi validation lab, power-loss matrix, soak test and pilot.

## P1 — Peripheral/product readiness

- [ ] Add semantic peripheral classification: keyboard, mouse, HID scanner, touchscreen, receipt printer, label printer, A4 printer, storage, serial adapter and unknown.
- [ ] Add hotplug-aware peripheral inventory to the Hardware Manager API and admin GUI.
- [ ] Add regression fixtures for USB HID keyboard, mouse and barcode scanner classification.
- [ ] Add end-to-end barcode acceptance harness for EAN-8, EAN-13 and Code 128 input with Enter/Tab suffix behavior.
- [ ] Add physical scanner acceptance checklist for layout correctness and rapid repeated scans.
- [ ] Extend printer onboarding from CUPS queue visibility to discovery, capability check, role selection, test print and reversible default assignment.
- [ ] Physically test keyboard, mouse, scanner, printer and optional touchscreen on the exact release image.
- [ ] Keep automatic thermal shutdown disabled until physical emergency-temperature validation passes.

## P2 — Operability and release discipline

- [ ] Generate a machine-readable release-readiness manifest tying source SHA, image SHA, CI/QEMU evidence and hardware evidence together.
- [ ] Build a redacted bounded diagnostic bundle for support.
- [ ] Document known limitations for every candidate release.
- [ ] Remove/retire temporary validation workflows only after their permanent equivalent is proven in the canonical release pipeline.
- [ ] Require new product changes to produce a fresh checksummed image and repeat both QEMU host paths before production approval.

## Current first implementation slice

- [x] Document the production blockers and current known limitations.
- [x] Create an explicit peripheral acceptance draft (#91) without mixing product and QEMU harness code.
- [ ] Implement semantic peripheral classification on a separate product branch.
- [ ] Add regression tests first, then expose classification through the Hardware Manager snapshot/API.
- [ ] Extend the admin hardware view to show device type, readiness and actionable setup state.
