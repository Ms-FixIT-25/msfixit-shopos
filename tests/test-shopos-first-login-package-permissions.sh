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

python3 - "$build" <<'PY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text(encoding='utf-8')
chmod = re.search(r'(?ms)^chmod 0755 \\\n(?P<body>.*?)^chmod 0644 ', text)
if not chmod or 'msfixit-first-login-init' not in chmod.group('body'):
    raise SystemExit('FAIL: first-login-init is not forced to mode 0755 during package staging')
hash_call = re.search(r'(?ms)sha256sum \\\n(?P<body>.*?)(?:\n\s*\)|\n\s*>|\n\s*\})', text)
if not hash_call or 'usr/local/sbin/msfixit-first-login-init' not in hash_call.group('body'):
    raise SystemExit('FAIL: first-login-init is absent from packaged build-info integrity hashes')
PY

printf 'PASS: first-login helper is packaged executable and integrity-tracked\n'
