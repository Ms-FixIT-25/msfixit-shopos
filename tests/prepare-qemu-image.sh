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

install -d -m 0755 "$mount_dir/var/lib/systemd"
head -c 512 /dev/urandom > "$mount_dir/var/lib/systemd/random-seed"
chmod 0600 "$mount_dir/var/lib/systemd/random-seed"

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

# Physical display/input flows cannot be validated by a headless emulated Pi.
# Mask them only in this disposable copy. The completion marker prevents getty
# or future units from trying to reopen the interactive first-login wizard.
install -d -m 0700 "$mount_dir/var/lib/msfixit-shopos"
touch "$mount_dir/var/lib/msfixit-shopos/first-setup-complete"
chmod 0600 "$mount_dir/var/lib/msfixit-shopos/first-setup-complete"
ln -sf /dev/null "$mount_dir/etc/systemd/system/msfixit-first-login.service"
ln -sf /dev/null "$mount_dir/etc/systemd/system/msfixit-boot-console.service"
ln -sf /dev/null "$mount_dir/etc/systemd/system/msfixit-kiosk.service"

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
printf 'Prepared QEMU guest with random seed, offline ordering, skipped physical first-login/display flows and bounded diagnostics.\n'
