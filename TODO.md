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

- [x] Add semantic peripheral classification: keyboard, mouse, HID scanner, touchscreen, receipt printer, label printer, A4 printer, storage, serial adapter and unknown. **Implemented + CI-tested in Draft #93; not yet QEMU-/physical-approved.**
- [ ] Add persistent hotplug-aware peripheral inventory to the Hardware Manager API. **Current snapshot/admin view refreshes connected devices every 15 seconds in #93; connect/disconnect history and stable device identity are still open.**
- [x] Add regression fixtures for USB HID keyboard, mouse and barcode scanner classification. **CI-tested in #93.**
- [x] Extend the admin hardware view with semantic device type, capability flags and conservative readiness state. **Admin Foundation #86/#87 and Integrated Validation #162 passed during this slice.**
- [x] Add a local scanner acceptance harness for EAN-8, EAN-13 and bounded generic scanner text. **Known-valid/invalid EAN checks, control-character handling and input bounds are CI-tested in #93.**
- [ ] Complete physical scanner acceptance for Enter/Tab suffix behavior, layout correctness, rapid repeated scans, reconnect and scanner-present-at-boot.
- [ ] Extend printer onboarding from CUPS queue visibility to discovery, capability check, exact device-to-queue mapping, role selection, test print and reversible default assignment.
- [ ] Physically test keyboard, mouse, scanner, printer and optional touchscreen on the exact release image.
- [ ] Keep automatic thermal shutdown disabled until physical emergency-temperature validation passes.

## P2 — Operability and release discipline

- [ ] Generate a machine-readable release-readiness manifest tying source SHA, image SHA, CI/QEMU evidence and hardware evidence together.
- [ ] Build a redacted bounded diagnostic bundle for support.
- [ ] Document known limitations for every candidate release.
- [ ] Remove/retire temporary validation workflows only after their permanent equivalent is proven in the canonical release pipeline.
- [ ] Require new product changes to produce a fresh checksummed image and repeat both QEMU host paths before production approval.

## Current implementation slice

- [x] Document the production blockers and current known limitations.
- [x] Create an explicit peripheral acceptance draft (#91) without mixing product and QEMU harness code.
- [x] Implement semantic peripheral classification on a separate product branch (#93).
- [x] Run the classification regression in integrated CI; the initial false-green coverage gap was found and corrected.
- [x] Extend the admin hardware view to show device type, capabilities and readiness without privileged device actions.
- [x] Add authenticated local `/admin/scanner-test` with testable EAN validation and no scan persistence.
- [x] Fix the build workflow so integration-targeted product PRs produce exact Raspberry Pi candidate images; Build #445 is the first run for this path.
- [ ] Add persistent hotplug connect/disconnect events with privacy-safe device identity.
- [ ] Add exact printer onboarding/test-print flow.
- [ ] After Build #445 succeeds, pin its artifact/digest and rerun 2× x86_64 + 2× ARM64 QEMU before calling the new peripheral work system-validated.
