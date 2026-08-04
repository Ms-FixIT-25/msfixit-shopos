#!/usr/bin/env bash
set -Eeuo pipefail

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

sync
printf 'Prepared QEMU guest with a fresh random seed and offline service ordering.\n'
