#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:?usage: postprocess-ab-image.sh RAW_IMAGE}"
[ "$(id -u)" -eq 0 ] || { echo 'must run as root' >&2; exit 1; }
[ -f "$image" ] && [ ! -L "$image" ] || { echo 'raw image must be a regular file' >&2; exit 1; }

for cmd in losetup lsblk sfdisk blockdev e2label tune2fs partprobe udevadm dd mount umount mountpoint python3; do
    command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }
done

loop=""
boot_mount=""
cleanup() {
    if [ -n "$boot_mount" ] && mountpoint -q "$boot_mount"; then
        umount "$boot_mount" 2>/dev/null || true
    fi
    if [ -n "$boot_mount" ]; then
        rmdir "$boot_mount" 2>/dev/null || true
    fi
    if [ -n "$loop" ]; then
        losetup -d "$loop" 2>/dev/null || true
    fi
}
trap cleanup EXIT

loop="$(losetup --find --show --partscan "$image")"
mapfile -t parts < <(lsblk -nrpo NAME,TYPE "$loop" | awk '$2=="part"{print $1}')
[ "${#parts[@]}" -eq 2 ] || { echo "expected exactly boot and root partitions, found ${#parts[@]}" >&2; exit 1; }
root_a="${parts[1]}"

root_size="$(blockdev --getsz "$root_a")"
[ "$root_size" -gt 0 ] || { echo 'invalid root partition size' >&2; exit 1; }
sector_size="$(blockdev --getss "$loop")"
align_sectors=$((8 * 1024 * 1024 / sector_size))
old_sectors="$(blockdev --getsz "$loop")"

losetup -d "$loop"
loop=""
truncate -s $(((old_sectors + align_sectors + root_size) * sector_size)) "$image"

loop="$(losetup --find --show --partscan "$image")"
boot_part="${loop}p1"
root_a="${loop}p2"
start_b=$((old_sectors + align_sectors))
printf '%s,%s,L\n' "$start_b" "$root_size" | sfdisk --append --no-reread "$loop"
partprobe "$loop"
udevadm settle
root_b="${loop}p3"
[ -b "$root_b" ] || { echo 'root B partition was not created' >&2; exit 1; }

dd if="$root_a" of="$root_b" bs=16M conv=fsync status=progress
sync
e2label "$root_a" SHOPOS_ROOT_A
e2label "$root_b" SHOPOS_ROOT_B
tune2fs -U random "$root_b" >/dev/null

e2label "$root_a" | grep -Fxq SHOPOS_ROOT_A
e2label "$root_b" | grep -Fxq SHOPOS_ROOT_B

# rpi-image-gen writes its original single-slot root path into cmdline.txt.
# Once the image is converted to ShopOS A/B that path no longer exists, so the
# very first boot must explicitly select the newly labelled Slot A filesystem.
# Enforce consoleblank=0 here as well, on the final mounted boot partition. The
# package postinst can run before /boot/firmware is available during image
# construction, so relying on postinst alone can leave the released image with
# the kernel's default console blanking timeout.
boot_mount="$(mktemp -d)"
mount "$boot_part" "$boot_mount"
cmdline="$boot_mount/cmdline.txt"
[ -f "$cmdline" ] && [ ! -L "$cmdline" ] || { echo 'boot cmdline.txt is missing or unsafe' >&2; exit 1; }
python3 - "$cmdline" <<'PY'
from pathlib import Path
import os
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
if '\n' in text.rstrip('\n'):
    raise SystemExit('kernel cmdline must contain exactly one line')
tokens = text.strip().split()
roots = [index for index, token in enumerate(tokens) if token.startswith('root=')]
if len(roots) != 1:
    raise SystemExit('kernel cmdline must contain exactly one root parameter')
tokens[roots[0]] = 'root=LABEL=SHOPOS_ROOT_A'
tokens = [token for token in tokens if not token.startswith('consoleblank=')]
tokens.append('consoleblank=0')
if tokens.count('consoleblank=0') != 1:
    raise SystemExit('kernel cmdline must contain exactly one consoleblank=0 parameter')
tmp = path.with_name('.cmdline.shopos.tmp')
tmp.write_text(' '.join(tokens) + '\n', encoding='utf-8')
os.replace(tmp, path)
PY
sync
umount "$boot_mount"
rmdir "$boot_mount"
boot_mount=""

cat > "${image}.ab-layout" <<EOF
schema=1
boot_partition=1
root_a_partition=2
root_b_partition=3
root_a_label=SHOPOS_ROOT_A
root_b_label=SHOPOS_ROOT_B
initial_root=LABEL=SHOPOS_ROOT_A
root_partition_sectors=${root_size}
EOF

# Only final compressed artifacts are checksummed. Hashing the temporary raw
# A/B image forced an extra full read without adding release integrity.
echo "A/B layout created with initial root SHOPOS_ROOT_A: $image"
