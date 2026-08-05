# ShopOS Hardware Validation Protocol

Production approval requires evidence from the exact published image, not a locally rebuilt approximation.

## Required evidence

Each run must record:

- exact Git commit SHA
- exact compressed or raw image SHA-256 and byte size
- stable lab device identifier and hardware model
- kernel, OS, active root source, partition label and kernel command line
- one result for every executed scenario
- explicit `blocked` results where the fixture or prerequisite is missing

Generate the signed-off JSON record with:

```bash
python3 scripts/hardware-validation-report.py \
  --image artifacts/msfixit-shopos-rpi4-usb.img \
  --commit "$(git rev-parse HEAD)" \
  --device-id pi4-usb-lab-01 \
  --results validation-results.json \
  --output validation-report.json
```

## Minimum Raspberry Pi 4 USB-SSD gate

1. Flash and verify the exact production artifact.
2. Cold boot Slot A five times.
3. Select and boot Slot B five times.
4. Stage a trial update, withhold health confirmation and verify automatic rollback.
5. Repeat interruption tests during first boot, update write, database write and backup creation.
6. Fill the root filesystem and confirm controlled failure without corruption.
7. Remove network and DNS independently and verify local administration remains usable.
8. Set the clock substantially backward and forward and verify update rejection rules.
9. Run a 72-hour workload soak with periodic storefront, database, backup and reboot checks.
10. Restore the latest backup to replacement media and verify the storefront and administration state.

## Power interruption rules

Use a switched power fixture; do not pull storage media while powered. Record the exact interruption phase and repetition count. A scenario passes only when the device either resumes safely or rolls back automatically without unexplained data loss.

Run each destructive interruption point at least ten times. Any filesystem repair, manual slot selection, missing order, damaged database table or unrecoverable boot counts as a failure and blocks production approval.

## Results file

The input is a strict JSON array. Supported test names are defined in `hardware-validation-report.py` and cannot be extended ad hoc without review.

```json
[
  {
    "test": "boot-slot-a",
    "result": "pass",
    "notes": "Five cold boots; active root label SHOPOS_ROOT_A."
  },
  {
    "test": "power-loss-update",
    "result": "blocked",
    "notes": "Switched power fixture not yet installed."
  }
]
```

Allowed result values are `pass`, `fail`, and `blocked`. A generated report exits non-zero when any scenario failed, making it suitable for a lab runner or later self-hosted GitHub Actions integration.
