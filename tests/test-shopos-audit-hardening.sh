#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
admin="$root/image/package/usr/share/msfixit-shopos/admin-console/public/index.php"
updates="$root/image/package/usr/share/msfixit-shopos/admin-console/public/updates.php"
backup="$root/image/package/usr/local/sbin/msfixit-backup"
control="$root/image/package/DEBIAN/control"
vendor="$root/scripts/fetch-vendor-assets.sh"
build="$root/scripts/build-package.sh"
qemu="$root/tests/run-qemu-smoke.sh"
cloud="$root/image/package/usr/local/sbin/msfixit-cloudflared-run"

for file in "$admin" "$updates" "$backup" "$control" "$vendor" "$build" "$qemu" "$cloud"; do
    test -s "$file"
done

if grep -Eq '(shell_exec|passthru|pcntl_exec)[[:space:]]*\(' "$admin" "$updates"; then
    echo 'Admin PHP must not execute commands through a shell primitive.' >&2
    exit 1
fi
grep -Fq "['bypass_shell' => true]" "$admin"
grep -Fq "['bypass_shell'=>true]" "$updates"
grep -Fq 'proc_get_status' "$admin"
grep -Fq 'proc_terminate' "$admin"
grep -Fq 'microtime(true)' "$updates"
grep -Fq 'proc_terminate' "$updates"
grep -Fq 'return[124' "$updates"

grep -Fq 'shopos-${stamp}.tar.zst' "$backup"
grep -Fq "glob('/data/backups/shopos-*.tar.zst')" "$admin"
grep -Eq '^Depends:.*(^|, )zstd(,|$)' "$control"

grep -Eq '^Depends:.*(^|, )avahi-daemon(,|$)' "$control"
grep -Eq '^Depends:.*(^|, )libnss-mdns(,|$)' "$control"

grep -Eq 'woocommerce_sha256=.*[0-9a-f]{64}' "$vendor"
grep -Fq 'sha256sum --check --strict' "$vendor"
grep -Fq 'WOOCOMMERCE_SHA256=' "$build"

grep -Fq 'SOURCE_DATE_EPOCH' "$build"
grep -Fq 'git -C "$root" log -1 --format=%ct' "$build"
grep -Fq 'touch --no-dereference --date="@${SOURCE_DATE_EPOCH}"' "$build"
if grep -Fq 'BUILD_UTC=%s' "$build"; then
    echo 'Build metadata must not embed a live wall-clock timestamp.' >&2
    exit 1
fi

grep -Fq -- "-accel 'tcg,thread=multi'" "$qemu"
if grep -Fq -- '-accel tcg,thread=multi' "$qemu"; then
    echo 'QEMU TCG accelerator must stay one quoted array element.' >&2
    exit 1
fi

grep -Fq 'msfixit-cloudflared-run' "$build"
grep -Fq -- '--token-file' "$cloud"

printf 'PASS: repository audit hardening contracts remain enforced.\n'
