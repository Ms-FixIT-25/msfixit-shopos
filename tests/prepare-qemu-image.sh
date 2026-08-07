#!/usr/bin/env bash
set -Eeuo pipefail

wait_for_loop_partition() {
    local partition="$1" attempts="${2:-50}" delay="${3:-0.2}"
    local attempt

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if [ -b "$partition" ]; then
            return 0
        fi
        command -v udevadm >/dev/null 2>&1 && udevadm settle --timeout=1 2>/dev/null || true
        sleep "$delay"
    done

    printf 'Timed out waiting for loop partition %s after %s attempts.\n' "$partition" "$attempts" >&2
    command -v lsblk >/dev/null 2>&1 && lsblk >&2 || true
    return 1
}

if [ "${1:-}" = "--self-test" ]; then
    # Static/behavioral contract for the partition-discovery race: the helper
    # must reject a path that never becomes a block device within the bounded
    # retry window instead of falling through to mount immediately.
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    if wait_for_loop_partition "$tmp" 2 0.01; then
        echo 'Self-test unexpectedly accepted a regular file as a loop partition.' >&2
        exit 1
    fi
    echo 'prepare-qemu-image partition wait self-test passed.'
    exit 0
fi

image="${1:?usage: prepare-qemu-image.sh IMAGE}"
image="$(readlink -f "$image")"
loop=''
mount_dir="$(mktemp -d)"

cleanup() {
    umount "$mount_dir" 2>/dev/null || true
    if [ -n "$loop" ]; then
        losetup -d "$loop" 2>/dev/null || true
    fi
    rmdir "$mount_dir" 2>/dev/null || true
}
trap cleanup EXIT

loop="$(losetup --find --show --partscan "$image")"
# On hosted ARM64 runners the kernel/udev partition nodes can lag slightly
# behind losetup --partscan. Wait for both real image partitions before the
# first mount instead of treating that transient discovery race as a product
# boot failure.
command -v udevadm >/dev/null 2>&1 && udevadm settle --timeout=10 2>/dev/null || true
wait_for_loop_partition "${loop}p1"
wait_for_loop_partition "${loop}p2"
mount "${loop}p2" "$mount_dir"

# QEMU's Raspberry Pi 4 model disables the BCM2711 hardware RNG. Supply a
# fresh seed to the disposable guest so systemd can initialize the kernel CRNG
# before ShopOS generates database and administrator secrets.
install -d -m 0755 "$mount_dir/var/lib/systemd"
head -c 512 /dev/urandom > "$mount_dir/var/lib/systemd/random-seed"
chmod 0600 "$mount_dir/var/lib/systemd/random-seed"

# QEMU's raspi4b model has no emulated Ethernet controller. The real image
# correctly waits for network-online on physical hardware, but the acceptance
# guest should provision from its bundled offline payload without pointless
# wait-online delays. A documentation-only TEST-NET address on loopback also
# lets first boot determine a local address immediately.
install -d -m 0755 \
    "$mount_dir/etc/systemd/system/msfixit-firstboot.service.d" \
    "$mount_dir/etc/systemd/system/msfixit-brand-shop.service.d"

cat > "$mount_dir/etc/systemd/system/msfixit-firstboot.service.d/10-qemu-offline.conf" <<'EOF_FIRSTBOOT'
[Unit]
Wants=
After=
After=local-fs.target

[Service]
ExecStartPre=-/usr/sbin/ip address add 192.0.2.2/32 dev lo
Restart=no
TimeoutStartSec=15min
EOF_FIRSTBOOT

cat > "$mount_dir/etc/systemd/system/msfixit-brand-shop.service.d/10-qemu-offline.conf" <<'EOF_BRAND'
[Unit]
Wants=
After=
After=msfixit-firstboot.service
Requires=msfixit-firstboot.service

[Service]
Restart=no
TimeoutStartSec=15min
EOF_BRAND

# The appliance boot console and Chromium kiosk are physical-display features.
# Running Chromium under headless TCG would add heavy emulation load without
# validating pixels or input. Their package and systemd contracts are covered
# separately; mask both only in this disposable acceptance image.
ln -sf /dev/null "$mount_dir/etc/systemd/system/msfixit-boot-console.service"
ln -sf /dev/null "$mount_dir/etc/systemd/system/msfixit-kiosk.service"

# Keep a runaway driver or service from generating multi-gigabyte evidence.
# Preserve the bounded journal on disk so it can be inspected after QEMU exits.
install -d -m 0755 "$mount_dir/etc/systemd/journald.conf.d" "$mount_dir/var/log/journal"
cat > "$mount_dir/etc/systemd/journald.conf.d/10-qemu-bounded.conf" <<'EOF_JOURNAL'
[Journal]
Storage=persistent
SystemMaxUse=64M
SystemKeepFree=32M
RuntimeMaxUse=64M
RuntimeKeepFree=32M
MaxFileSec=5min
RateLimitIntervalSec=30s
RateLimitBurst=2000
ForwardToConsole=no
EOF_JOURNAL

sync
printf 'Prepared QEMU guest with random seed, offline ordering, masked display services and bounded diagnostics.\n'
