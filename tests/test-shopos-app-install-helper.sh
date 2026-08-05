#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/image/package/usr/local/sbin/msfixit-app-install-helper"

bash -n "$helper"
grep -Fq 'readonly INBOX=/var/lib/msfixit-shopos/app-inbox' "$helper"
grep -Fq '[[ $1 == install ]]' "$helper"
grep -Fq '[[ $app_id =~ $ID_RE ]]' "$helper"
grep -Fq '[[ $app_id == at.msfixit.shopos.* ]]' "$helper"
grep -Fq '[[ -f $package && ! -L $package ]]' "$helper"
grep -Fq "package must not be group/world writable" "$helper"
grep -Fq 'exec /usr/bin/python3 "$INSTALLER"' "$helper"
grep -Fq -- '--public-key "$KEY"' "$helper"
grep -Fq -- '--root "$APPS"' "$helper"
grep -Fq -- '--audit "$AUDIT"' "$helper"
! grep -Eq '(eval|bash -c|sh -c|curl|wget|apt|dnf|yum|pacman)' "$helper"
! grep -Eq '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/\.\.' "$helper"
printf 'PASS: privileged app helper exposes one fixed install operation with strict app-id, path, ownership and mode checks.\n'
