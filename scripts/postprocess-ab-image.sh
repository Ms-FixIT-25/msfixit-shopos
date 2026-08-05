#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:?usage: postprocess-ab-image.sh RAW_IMAGE}"
[ "$(id -u)" -eq 0 ] || { echo 'must run as root' >&2; exit 1; }
[ -f "$image" ] && [ ! -L "$image" ] || { echo 'raw image must be a regular file' >&2; exit 1; }

for cmd in losetup lsblk sfdisk blockdev e2label tune2fs partprobe udevadm dd sha256sum; do
    command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }
done

loop=""
cleanup() {
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
root_a="${loop}p2"
start_b=$((old_sectors + align_sectors))
printf '%s,%s,L\n' "$start_b" "$root_size" | sfdisk --append --no-reread "$loop"
partprobe "$loop"
udevadm settle
root_b="${loop}p3"
[ -b "$root_b" ] || { echo 'root B partition was not created' >&2; exit 1; }

dd if="$root_a" of="$root_b" bs=16M conv=fsync,status=progress
sync
e2label "$root_a" SHOPOS_ROOT_A
e2label "$root_b" SHOPOS_ROOT_B
tune2fs -U random "$root_b" >/dev/null

e2label "$root_a" | grep -Fxq SHOPOS_ROOT_A
e2label "$root_b" | grep -Fxq SHOPOS_ROOT_B

cat > "${image}.ab-layout" <<EOF
schema=1
boot_partition=1
root_a_partition=2
root_b_partition=3
root_a_label=SHOPOS_ROOT_A
root_b_label=SHOPOS_ROOT_B
root_partition_sectors=${root_size}
EOF
sha256sum "$image" > "${image}.sha256"

echo "A/B layout created: $image"
