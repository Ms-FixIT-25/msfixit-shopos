#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
firstboot="$root/image/package/usr/local/sbin/msfixit-firstboot"

test -f "$firstboot"
bash -n "$firstboot"

grep -Fq 'install -d -m 0711 "$data_dir"' "$firstboot"
grep -Fq 'install -d -o mysql -g mysql -m 0750 "$data_dir/mariadb"' "$firstboot"
grep -Fq 'install -d -o www-data -g www-data -m 0750 "$data_dir/wordpress"' "$firstboot"
grep -Fq 'install -d -o www-data -g www-data -m 0750 "$data_dir/wordpress/uploads"' "$firstboot"

chown_line="$(grep -nF 'chown -R mysql:mysql "$data_dir/mariadb"' "$firstboot" | head -n1 | cut -d: -f1)"
init_line="$(grep -nF 'mariadb-install-db --user=mysql --datadir="$data_dir/mariadb" --skip-test-db' "$firstboot" | head -n1 | cut -d: -f1)"

test -n "$chown_line"
test -n "$init_line"
if [ "$chown_line" -ge "$init_line" ]; then
    printf 'MariaDB ownership must be repaired before mariadb-install-db runs.\n' >&2
    exit 1
fi

printf 'PASS: first-boot storage root is traversable and service directories are owned before initialization.\n'
