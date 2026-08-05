#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
page="$root/image/package/usr/share/msfixit-shopos/admin-console/public/oobe.php"
helper="$root/image/package/usr/local/sbin/msfixit-oobe-apply"
sudoers="$root/image/package/etc/sudoers.d/msfixit-shopos-oobe"

check() {
    local label="$1"
    shift
    if ! "$@"; then
        printf 'FAIL: %s\n' "$label" >&2
        exit 1
    fi
    printf 'PASS: %s\n' "$label"
}

check 'OOBE PHP syntax' php -l "$page"
check 'OOBE helper Python syntax' python3 -m py_compile "$helper"
check 'wizard step contract' grep -Fq "const STEPS=['welcome','locale','network','identity','license','apps','summary','apply','complete']" "$page"
check 'CSRF validation' grep -Fq "hash_equals(csrf()" "$page"
check 'password hashing' grep -Fq 'password_hash($p1,PASSWORD_DEFAULT)' "$page"
check 'shell-free proc_open invocation' grep -Fq 'proc_open($cmd' "$page"
check 'proc_open bypass_shell' grep -Fq "'bypass_shell'=>true" "$page"
check 'static IPv4 validation' grep -Fq 'filter_var($ip,FILTER_VALIDATE_IP' "$page"
check 'signed-license disclosure' grep -Fq 'Professional und Enterprise werden erst nach einer gültig signierten Lizenz' "$page"
check 'explicit setup confirmation' grep -Fq 'Einstellungen prüfen und Einrichtung starten' "$page"
check 'strict helper schema' grep -Fq 'if not isinstance(data,dict) or set(data)!=ALLOWED' "$helper"
check 'single-use setup guard' grep -Fq 'first-boot setup already completed' "$helper"
check 'symlink rejection' grep -Fq 'request.is_symlink()' "$helper"
check 'unsafe write-mode rejection' grep -Fq '(st.st_mode & 0o022)' "$helper"
check 'atomic persistence' grep -Fq 'os.replace(tmp,path)' "$helper"
check 'narrow sudoers rule' grep -Fxq 'www-data ALL=(root) NOPASSWD: /usr/local/sbin/msfixit-oobe-apply /run/shopos-oobe-*' "$sudoers"

if grep -Eq '(shell_exec|system\(|passthru\(|eval\(|bash -c|sh -c|curl|wget|apt |dnf |yum )' "$page" "$helper"; then
    printf 'FAIL: forbidden command execution primitive present\n' >&2
    exit 1
fi
printf 'PASS: no forbidden command execution primitives\n'

if grep -RiE '(PRIVATE KEY|master[_ -]?key|universal bypass)' "$page" "$helper" "$sudoers"; then
    printf 'FAIL: forbidden embedded key or bypass marker present\n' >&2
    exit 1
fi
printf 'PASS: no embedded private key or universal bypass\n'

printf 'PASS: first-boot OOBE is allowlisted, CSRF protected, shell-free, single-use and atomically persisted.\n'
