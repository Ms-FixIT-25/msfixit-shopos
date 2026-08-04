#!/usr/bin/env bash
set -Eeuo pipefail

select_initramfs() {
    local boot_dir="$1"
    find "$boot_dir" -maxdepth 1 -type f \
        \( -name 'initramfs*' -o -name 'initrd.img-*' \) \
        -printf '%f\n' \
        | sort -V \
        | tail -n 1
}

filesystem_uuid() {
    local device="$1" mountpoint="$2" uuid
    uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
    if [ -z "$uuid" ]; then
        uuid="$(findmnt -n -o UUID --target "$mountpoint" 2>/dev/null || true)"
    fi
    printf '%s' "$uuid"
}

rewrite_fstab_for_vm() {
    local fstab="$1" boot_uuid="$2" root_uuid="$3" tmp
    tmp="${fstab}.vm-new"
    awk -v boot="UUID=${boot_uuid}" -v root="UUID=${root_uuid}" '
        BEGIN { OFS="\t" }
        /^[[:space:]]*#/ || NF == 0 { print; next }
        $2 == "/boot/firmware" { $1 = boot; print; next }
        $2 == "/" { $1 = root; print; next }
        { print }
    ' "$fstab" > "$tmp"
    mv "$tmp" "$fstab"
}

bounded_copy() {
    local source="$1" destination="$2" maximum_bytes="$3"
    local size head_bytes tail_bytes
    [ -f "$source" ] || return 1
    size="$(stat -c '%s' "$source")"
    if [ "$size" -le "$maximum_bytes" ]; then
        cp "$source" "$destination"
        return 0
    fi

    head_bytes=$((maximum_bytes / 4))
    tail_bytes=$((maximum_bytes - head_bytes))
    {
        printf '--- LOG TRUNCATED: original bytes=%s, retained head=%s and tail=%s ---\n' \
            "$size" "$head_bytes" "$tail_bytes"
        head -c "$head_bytes" "$source"
        printf '\n--- OMITTED MIDDLE ---\n'
        tail -c "$tail_bytes" "$source"
    } > "$destination"
}

if [ "${1:-}" = '--self-test' ]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    touch "$tmp/initramfs_6.17.0-rpi-v8.img"
    touch "$tmp/initramfs_6.18.39+rpt-rpi-v8.img"
    selected="$(select_initramfs "$tmp")"
    test "$selected" = 'initramfs_6.18.39+rpt-rpi-v8.img'

    cat > "$tmp/fstab" <<'EOF_FSTAB'
# ShopOS storage slots
/dev/disk/by-slot/root / ext4 defaults 0 1
/dev/disk/by-slot/boot /boot/firmware vfat defaults 0 2
EOF_FSTAB
    rewrite_fstab_for_vm "$tmp/fstab" 'BOOT-1234' '11111111-2222-3333-4444-555555555555'
    grep -Eq '^UUID=11111111-2222-3333-4444-555555555555[[:space:]]+/[[:space:]]+ext4' "$tmp/fstab"
    grep -Eq '^UUID=BOOT-1234[[:space:]]+/boot/firmware[[:space:]]+vfat' "$tmp/fstab"

    printf 'head-data\n' > "$tmp/large.log"
    dd if=/dev/zero bs=1024 count=16 status=none >> "$tmp/large.log"
    printf 'tail-data\n' >> "$tmp/large.log"
    bounded_copy "$tmp/large.log" "$tmp/bounded.log" 4096
    test "$(stat -c '%s' "$tmp/bounded.log")" -lt 8192
    grep -aq 'LOG TRUNCATED' "$tmp/bounded.log"

    printf 'PASS: versioned Raspberry Pi initramfs discovery (%s)\n' "$selected"
    printf 'PASS: VM fstab rewrite uses stable filesystem UUIDs\n'
    printf 'PASS: evidence logs are bounded before upload\n'
    exit 0
fi

image="${1:?usage: run-qemu-smoke.sh IMAGE OUTPUT_DIR}"
output_dir="${2:?usage: run-qemu-smoke.sh IMAGE OUTPUT_DIR}"
mkdir -p "$output_dir"
image="$(readlink -f "$image")"
output_dir="$(readlink -f "$output_dir")"

command -v qemu-system-aarch64 >/dev/null
qemu-system-aarch64 --version | tee "$output_dir/qemu-version.txt"
qemu-system-aarch64 -machine help | grep -q '^raspi4b '

loop=''
cleanup_mounts() {
    umount /mnt/shopos-boot 2>/dev/null || true
    umount /mnt/shopos-root 2>/dev/null || true
    if [ -n "$loop" ]; then
        losetup -d "$loop" 2>/dev/null || true
    fi
}
trap cleanup_mounts EXIT

loop="$(losetup --find --show --partscan "$image")"
mkdir -p /mnt/shopos-boot /mnt/shopos-root
mount "${loop}p1" /mnt/shopos-boot
mount "${loop}p2" /mnt/shopos-root

boot_uuid="$(filesystem_uuid "${loop}p1" /mnt/shopos-boot)"
root_uuid="$(filesystem_uuid "${loop}p2" /mnt/shopos-root)"
test -n "$boot_uuid"
test -n "$root_uuid"
printf 'Boot filesystem UUID: %s\nRoot filesystem UUID: %s\n' "$boot_uuid" "$root_uuid" | tee "$output_dir/partition-identifiers.txt"

# The production image intentionally mounts partitions through Raspberry Pi
# storage-slot aliases. QEMU presents the disposable image as an emulated SD
# card and does not create /dev/disk/by-slot/boot. Rewrite only the disposable
# test copy to stable filesystem UUID sources so systemd can reach local-fs.target.
cp /mnt/shopos-root/etc/fstab "$output_dir/fstab.before"
rewrite_fstab_for_vm /mnt/shopos-root/etc/fstab "$boot_uuid" "$root_uuid"
cp /mnt/shopos-root/etc/fstab "$output_dir/fstab.after"
grep -Eq "^UUID=${boot_uuid}[[:space:]]+/boot/firmware[[:space:]]" /mnt/shopos-root/etc/fstab
grep -Eq "^UUID=${root_uuid}[[:space:]]+/[[:space:]]+ext4" /mnt/shopos-root/etc/fstab

test -s /mnt/shopos-boot/kernel8.img
test -s /mnt/shopos-boot/bcm2711-rpi-4-b.dtb
cp /mnt/shopos-boot/kernel8.img "$output_dir/kernel8.img"
cp /mnt/shopos-boot/bcm2711-rpi-4-b.dtb "$output_dir/bcm2711-rpi-4-b.dtb"

initramfs_name="$(select_initramfs /mnt/shopos-boot)"
if [ -z "$initramfs_name" ]; then
    printf 'No Raspberry Pi initramfs was found in the boot partition.\n' >&2
    find /mnt/shopos-boot -maxdepth 1 -type f -printf '%f\n' | sort >&2
    exit 1
fi
initrd="$output_dir/initramfs.img"
cp "/mnt/shopos-boot/$initramfs_name" "$initrd"
printf 'Selected initramfs: %s\n' "$initramfs_name" | tee "$output_dir/initramfs-selection.txt"
test -s "$initrd"

if ! grep -Eq '^enable_uart=1$' /mnt/shopos-boot/config.txt; then
    printf '\nenable_uart=1\n' >> /mnt/shopos-boot/config.txt
fi

cat > /mnt/shopos-boot/shopos.env <<'EOF_CONFIG'
SHOP_URL=http://127.0.0.1
SHOP_TITLE=Ms. FixIT ShopOS VM Test
SHOP_ADMIN_USER=shopadmin
SHOP_ADMIN_EMAIL=office@msfixit.at
SHOP_ADMIN_PASSWORD=VmTest-Only-ChangeMe-2026
OS_ADMIN_PASSWORD=VmTest-Only-ChangeMe-2026
WORDPRESS_LOCALE=de_DE
WORDPRESS_VERSION=7.0.2
EOF_CONFIG
chmod 0600 /mnt/shopos-boot/shopos.env

install -d -m 0755 /mnt/shopos-root/usr/local/sbin
cat > /mnt/shopos-root/usr/local/sbin/msfixit-vm-smoke <<'EOF_SMOKE'
#!/usr/bin/env bash
set -u
exec > >(tee -a /var/log/msfixit-vm-smoke.log /dev/console 2>/dev/null) 2>&1

failures=0
check() {
    local label="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$label"
    else
        printf 'FAIL: %s\n' "$label"
        failures=$((failures + 1))
    fi
}

printf 'MSFIXIT_VM_SMOKE_BEGIN\n'
printf 'Kernel: %s\n' "$(uname -a)"
printf 'Architecture: %s\n' "$(uname -m)"

finished=no
for _ in $(seq 1 300); do
    if [ -e /data/.shopos-ready ]; then
        finished=yes
        break
    fi
    if systemctl is-failed --quiet msfixit-firstboot.service \
        || systemctl is-failed --quiet msfixit-brand-shop.service; then
        break
    fi
    sleep 5
done

if [ "$finished" != yes ]; then
    printf 'ShopOS did not reach the ready marker before a service failed or the 25-minute guest watchdog expired.\n'
fi

systemctl --no-pager --full status msfixit-firstboot.service msfixit-brand-shop.service || true
check 'boot partition mounted' mountpoint -q /boot/firmware
check 'initialization marker' test -e /data/.shopos-initialized
check 'ready marker' test -e /data/.shopos-ready
check 'credentials file' test -s /boot/firmware/SHOPOS-CREDENTIALS.txt
check 'MariaDB active' systemctl is-active --quiet mariadb.service
check 'Redis active' systemctl is-active --quiet redis-server.service
check 'Nginx active' systemctl is-active --quiet nginx.service

php_service="$(systemctl list-unit-files --type=service --no-legend 'php*-fpm.service' 2>/dev/null | awk 'NR==1 {print $1}')"
check 'PHP-FPM discovered' test -n "$php_service"
if [ -n "$php_service" ]; then
    check 'PHP-FPM active' systemctl is-active --quiet "$php_service"
fi

check 'WordPress files' test -s /srv/www/wordpress/wp-load.php
check 'WordPress installed' runuser -u www-data -- env HOME=/tmp /usr/local/bin/wp --path=/srv/www/wordpress core is-installed
check 'WooCommerce active' runuser -u www-data -- env HOME=/tmp /usr/local/bin/wp --path=/srv/www/wordpress plugin is-active woocommerce
check 'Redis plugin active' runuser -u www-data -- env HOME=/tmp /usr/local/bin/wp --path=/srv/www/wordpress plugin is-active redis-cache
check 'customer authentication installed' test -s /usr/share/msfixit-shopos/wordpress/msfixit-customer-auth.php
check 'service portal installed' test -s /usr/share/msfixit-shopos/wordpress/msfixit-service-requests.php
check 'Workspace mail installed' test -s /usr/share/msfixit-shopos/wordpress/msfixit-workspace.php
check 'local HTTP response' curl --fail --silent --show-error --max-time 30 http://127.0.0.1/
check 'version command' /usr/local/bin/shopos-version

printf '\nFirst-boot log tail:\n'
tail -n 200 /var/log/msfixit-firstboot.log 2>/dev/null || true
printf '\nFailed units:\n'
systemctl --failed --no-pager --full || true

if [ "$failures" -eq 0 ]; then
    result=PASS
else
    result=FAIL
fi
printf 'MSFIXIT_VM_SMOKE_RESULT=%s failures=%s\n' "$result" "$failures"
printf 'MSFIXIT_VM_SMOKE_RESULT=%s failures=%s\n' "$result" "$failures" > /var/log/msfixit-vm-smoke.result
sync
systemctl poweroff --no-block || true
exit 0
EOF_SMOKE
chmod 0755 /mnt/shopos-root/usr/local/sbin/msfixit-vm-smoke

cat > /mnt/shopos-root/etc/systemd/system/msfixit-vm-smoke.service <<'EOF_UNIT'
[Unit]
Description=Ms. FixIT ShopOS QEMU acceptance smoke test and watchdog
After=local-fs.target
Wants=msfixit-firstboot.service msfixit-brand-shop.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/msfixit-vm-smoke
TimeoutStartSec=27min

[Install]
WantedBy=multi-user.target
EOF_UNIT
install -d -m 0755 /mnt/shopos-root/etc/systemd/system/multi-user.target.wants
ln -sf ../msfixit-vm-smoke.service /mnt/shopos-root/etc/systemd/system/multi-user.target.wants/msfixit-vm-smoke.service

sync
cleanup_mounts
loop=''
trap - EXIT

# QEMU exposes the PL011 at fe201000 as ttyAMA1 with this Raspberry Pi 4 DTB.
# Using ttyAMA0 leaves the kernel without a usable /dev/console, so the
# initramfs shell exits with code 2 while redirecting run-init and PID 1 panics.
kernel_cmdline="earlycon=pl011,0xfe201000,115200 console=tty0 console=ttyAMA1,115200 root=UUID=${root_uuid} rootfstype=ext4 rootwait rw fsck.repair=yes loglevel=5 systemd.show_status=1 plymouth.enable=0 panic=5"
printf '%s\n' "$kernel_cmdline" | tee "$output_dir/kernel-command-line.txt"

qemu_args=(
    -machine raspi4b
    -accel tcg,thread=multi
    -kernel "$output_dir/kernel8.img"
    -dtb "$output_dir/bcm2711-rpi-4-b.dtb"
    -initrd "$initrd"
    -append "$kernel_cmdline"
    -drive "file=${image},format=raw,if=sd,cache=writeback"
    -display none
    -serial stdio
    -monitor none
    -no-reboot
)

qemu_full="$output_dir/qemu-console.full.log"
set +e
timeout --signal=TERM --kill-after=30s 32m qemu-system-aarch64 "${qemu_args[@]}" > "$qemu_full" 2>&1
qemu_rc=$?
set -e
printf 'QEMU_EXIT=%s\n' "$qemu_rc" | tee "$output_dir/qemu-exit.txt"
bounded_copy "$qemu_full" "$output_dir/qemu-console.log" $((16 * 1024 * 1024))
rm -f "$qemu_full"

loop="$(losetup --find --show --partscan "$image")"
trap cleanup_mounts EXIT
mount "${loop}p2" /mnt/shopos-root
bounded_copy /mnt/shopos-root/var/log/msfixit-vm-smoke.log "$output_dir/msfixit-vm-smoke.log" $((8 * 1024 * 1024)) 2>/dev/null || true
cp /mnt/shopos-root/var/log/msfixit-vm-smoke.result "$output_dir/" 2>/dev/null || true
bounded_copy /mnt/shopos-root/var/log/msfixit-firstboot.log "$output_dir/msfixit-firstboot.log" $((8 * 1024 * 1024)) 2>/dev/null || true

journal_tmp="$output_dir/guest-journal.full.log"
journalctl --directory=/mnt/shopos-root/var/log/journal --no-pager -b -n 5000 -o short-monotonic > "$journal_tmp" 2>/dev/null || true
if [ -f "$journal_tmp" ]; then
    bounded_copy "$journal_tmp" "$output_dir/guest-journal.log" $((16 * 1024 * 1024)) || true
    rm -f "$journal_tmp"
fi

{
    printf 'ShopOS marker files:\n'
    find /mnt/shopos-root/data -maxdepth 1 -type f -printf '%f %s bytes\n' 2>/dev/null | sort || true
    printf '\nPersistent log sizes:\n'
    du -ah /mnt/shopos-root/var/log/msfixit-* /mnt/shopos-root/var/log/journal 2>/dev/null | sort -h || true
    printf '\nInstalled systemd overrides:\n'
    find /mnt/shopos-root/etc/systemd/system -path '*msfixit*' -o -path '*journald*' 2>/dev/null | sort || true
} > "$output_dir/guest-filesystem-state.txt"

cleanup_mounts
loop=''
trap - EXIT

printf '\nLast QEMU console lines:\n'
tail -n 400 "$output_dir/qemu-console.log" || true
printf '\nGuest smoke result:\n'
cat "$output_dir/msfixit-vm-smoke.result" 2>/dev/null || true
printf '\nFirst-boot failure hints:\n'
grep -Ei 'fail|error|timeout|panic|fatal|denied|not found|cannot|unable' \
    "$output_dir/msfixit-firstboot.log" "$output_dir/guest-journal.log" 2>/dev/null \
    | tail -n 200 || true

grep -q 'MSFIXIT_VM_SMOKE_RESULT=PASS' "$output_dir/msfixit-vm-smoke.result"
