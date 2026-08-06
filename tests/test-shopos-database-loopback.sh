#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scripts=(
    "$root/image/package/usr/local/sbin/msfixit-catalog-init"
    "$root/image/package/usr/local/sbin/msfixit-office-init"
    "$root/image/package/usr/local/sbin/msfixit-partners-init"
)

for script in "${scripts[@]}"; do
    bash -n "$script"
    grep -Fq "@'localhost'" "$script"

    if grep -Eq '^[A-Z0-9_]+_DB_HOST=127\.0\.0\.1$' "$script"; then
        printf 'Database account/host mismatch in %s: localhost grants cannot be paired with a 127.0.0.1 runtime host.\n' "$script" >&2
        exit 1
    fi

done

grep -Fq 'CATALOG_DB_HOST=localhost' "${scripts[0]}"
test "$(grep -c '^OFFICE_DB_HOST=localhost$' "${scripts[1]}")" -eq 3
grep -Fq 'PARTNER_DB_HOST=localhost' "${scripts[2]}"

printf 'PASS: generated database endpoints match the local-only MariaDB account grants.\n'
