#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build="$root/scripts/build-package.sh"
service="$root/image/package/etc/systemd/system/msfixit-first-login.service"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[ -f "$build" ] || fail 'build-package.sh missing'
[ -f "$service" ] || fail 'first-login service missing'

grep -Fq 'ExecStart=/usr/local/sbin/msfixit-first-login-init' "$service" \
    || fail 'first-login service no longer executes the expected helper'

grep -Fq '"$stage/usr/local/sbin/msfixit-first-login-init"' "$build" \
    || fail 'package build does not explicitly include first-login-init in its executable chmod contract'

chmod_block="$(sed -n '/^chmod 0755 \\/,/^chmod 0644 /p' "$build")"
printf '%s\n' "$chmod_block" | grep -Fq 'msfixit-first-login-init' \
    || fail 'first-login-init is not forced to mode 0755 during package staging'

hash_block="$(sed -n '/^[[:space:]]*sha256sum \\/,/usr\/share\/msfixit-shopos\/wordpress\/assets\/msfixit-service-requests.css/p' "$build")"
printf '%s\n' "$hash_block" | grep -Fq 'usr/local/sbin/msfixit-first-login-init' \
    || fail 'first-login-init is absent from packaged build-info integrity hashes'

printf 'PASS: first-login helper is packaged executable and integrity-tracked\n'
