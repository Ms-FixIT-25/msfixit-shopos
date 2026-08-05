# ShopOS A/B slot integration

## Scope

This stage connects the signed update control plane to a constrained image writer and a persistent boot-selection contract. It does not repartition existing installations automatically.

## Fixed layout

Production images must provide these partition labels:

- `SHOPOS_ROOT_A`
- `SHOPOS_ROOT_B`

The only accepted device paths are:

- `/dev/disk/by-partlabel/SHOPOS_ROOT_A`
- `/dev/disk/by-partlabel/SHOPOS_ROOT_B`

The writer rejects arbitrary paths, unknown slots, mounted targets, symlink images, non-block targets, hash mismatches and size mismatches. Test mode permits regular files only when `SHOPOS_SLOT_WRITER_TEST=1` is explicitly set.

## Boot selection contract

The selected slot is persisted atomically in:

`/boot/firmware/shopos-slot.env`

The file contains only the validated slot and matching root label. The image-generation layer must consume this contract when it introduces the physical A/B partition table and bootloader integration.

## Boot and rollback flow

1. A signed manifest is verified by `msfixit-update`.
2. The inactive slot is selected by the state machine.
3. `msfixit-slot-writer` writes only that fixed target and verifies the written bytes again.
4. The new slot is selected for trial boot.
5. `msfixit-update-boot-sync.service` records each trial start before the application stack starts.
6. After the configured maximum of three unconfirmed starts, the state machine enters rollback and the boot selection is atomically restored to the previous slot.
7. A separate health-confirmation stage will mark a successful trial as confirmed only after database, web, storage and configuration checks pass.

## Remaining hardware gate

Before production enablement, the image builder must create the physical A/B layout and the Raspberry Pi boot chain must consume `shopos-slot.env`. Power must then be interrupted during write, selection, first boot, confirmation and rollback on the Raspberry Pi 4 USB-SSD reference platform.
