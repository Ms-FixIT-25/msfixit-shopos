#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
catalog_init="$root/image/package/usr/local/sbin/msfixit-catalog-init"
office_init="$root/image/package/usr/local/sbin/msfixit-office-init"
partners_init="$root/image/package/usr/local/sbin/msfixit-partners-init"
also_init="$root/image/package/usr/local/sbin/msfixit-also-init"
scripts=(
    "$catalog_init"
    "$office_init"
    "$partners_init"
    "$also_init"
)

for script in "${scripts[@]}"; do
    bash -n "$script"
done

for script in "$catalog_init" "$office_init" "$partners_init"; do
    grep -Fq "@'localhost'" "$script"

    if grep -Eq '^[A-Z0-9_]+_DB_HOST=127\.0\.0\.1$' "$script"; then
        printf 'Database account/host mismatch in %s: localhost grants cannot be paired with a 127.0.0.1 runtime host.\n' "$script" >&2
        exit 1
    fi
done

grep -Fq 'CATALOG_DB_HOST=localhost' "$catalog_init"
test "$(grep -c '^OFFICE_DB_HOST=localhost$' "$office_init")" -eq 3
grep -Fq 'PARTNER_DB_HOST=localhost' "$partners_init"

# MariaDB treats --port as a request for TCP. A local-only account granted as
# user@localhost must therefore be initialized through the Unix socket rather
# than accidentally arriving as user@127.0.0.1.
grep -Fq -- '--protocol=socket' "$also_init"
if grep -Fq -- '--port="$CATALOG_DB_PORT"' "$also_init"; then
    printf 'ALSO initialization must not force TCP for a localhost-only MariaDB account.\n' >&2
    exit 1
fi
if grep -Fq -- '--host="$CATALOG_DB_HOST"' "$also_init"; then
    printf 'ALSO initialization must use an explicit Unix socket, not an ambiguous host connection.\n' >&2
    exit 1
fi

printf 'PASS: generated database endpoints and local initialization protocols match MariaDB account grants.\n'
