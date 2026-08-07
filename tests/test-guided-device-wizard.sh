#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
detector="$root/image/package/usr/local/sbin/msfixit-device-detected"
action="$root/image/package/usr/local/sbin/msfixit-admin-action"
page="$root/image/package/usr/share/msfixit-shopos/admin-console/public/devices.php"
rule="$root/image/package/etc/udev/rules.d/90-msfixit-removable-storage.rules"
nginx="$root/image/package/etc/nginx/snippets/msfixit-admin-console.conf"

bash -n "$detector"
bash -n "$action"
php -l "$page"

grep -Fq 'Nothing is mounted automatically' "$rule"
grep -Fq 'msfixit-device-detected' "$rule"
grep -Fq 'findmnt -n -o SOURCE /' "$detector"
grep -Fq 'findmnt -n -o SOURCE /boot/firmware' "$detector"
grep -Fq 'sha256sum' "$detector"
grep -Fq 'chmod 0640' "$detector"
grep -Fq "case \"\$fstype\"" "$detector"

grep -Fq 'device-mount)' "$action"
grep -Fq 'device-ignore)' "$action"
grep -Fq "options='nosuid,nodev,noexec'" "$action"
grep -Fq 'read-only|read-write' "$action"
grep -Fq 'resolve_device_request' "$action"
grep -Fq 'blkid -o value -s TYPE' "$action"

grep -Fq "hash_equals(\$csrf, \$token)" "$page"
grep -Fq "authenticated" "$page"
grep -Fq 'Nur lesen – empfohlen' "$page"
grep -Fq 'Lesen und speichern' "$page"
grep -Fq 'Später entscheiden' "$page"
grep -Fq 'ShopOS bindet externe Datenträger nie ungefragt ein' "$page"
grep -Fq 'location = /admin/devices' "$nginx"
grep -Fq 'devices.php' "$nginx"

# There must be no generic mount of a raw POST value and no shell interpolation.
if grep -En 'mount .*\$_(POST|GET|REQUEST)|shell_exec\(' "$page"; then
    echo 'Unsafe user-controlled mount execution detected.' >&2
    exit 1
fi

printf 'PASS: removable media requires an authenticated, CSRF-protected, allowlisted user decision and mounts with nosuid,nodev,noexec.\n'
