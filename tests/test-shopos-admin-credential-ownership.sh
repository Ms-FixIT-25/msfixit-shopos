#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
firstboot="$root/image/package/usr/local/sbin/msfixit-firstboot"
first_login="$root/image/package/usr/local/sbin/msfixit-first-login-init"
apply_config="$root/image/package/usr/local/sbin/msfixit-apply-config"
example="$root/image/package/usr/share/msfixit-shopos/shopos.env.example"

bash -n "$firstboot"
bash -n "$first_login"
bash -n "$apply_config"

# Keep the searched variables literal. Expanding them in this regression test
# under `set -u` would make the test itself fail before inspecting the product.
grep -Fq 'printf '\''%s:%s\n'\'' "$username" "$password_one" | chpasswd' "$first_login"
grep -Fq '/etc/msfixit-shopos/admin-user' "$first_login"

if grep -Fq 'OS_ADMIN_PASSWORD' "$firstboot" "$apply_config" "$example"; then
    echo 'Unattended ShopOS configuration must not own the local Linux administrator password.' >&2
    exit 1
fi
if grep -Eq '(^|[[:space:]])chpasswd([[:space:]]|$)' "$firstboot" "$apply_config"; then
    echo 'Only the interactive first-login wizard may change local Linux account passwords.' >&2
    exit 1
fi
if grep -Fq 'SSH password:' "$firstboot"; then
    echo 'Firstboot credentials file must not persist or claim a Linux/SSH password.' >&2
    exit 1
fi

grep -Fq 'Linux administrator password: never written by firstboot' "$firstboot"
grep -Eq 'Linux/SSH administrator password.*interactiv' "$example"

printf 'PASS: local Linux administrator credentials have one interactive owner and are never persisted by unattended firstboot.\n'
