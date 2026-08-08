#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
client="$root/image/package/usr/local/lib/msfixit-shopos/ota-notify.py"
service="$root/image/package/etc/systemd/system/msfixit-ota-notify.service"
boot_sync="$root/image/package/etc/systemd/system/msfixit-update-boot-sync.service"
config="$root/image/package/etc/msfixit-shopos/ota-notify.json"

python3 -m py_compile "$client"
python3 "$client" --self-test
python3 - <<PY
import json
from pathlib import Path
cfg = json.loads(Path('$config').read_text())
assert cfg['schema'] == 1
assert cfg['enabled'] is False
assert cfg['endpoint'] == ''
assert cfg['channel'] == 'stable'
assert 10 <= cfg['long_poll_seconds'] <= 120
assert cfg['minimum_wake_interval_seconds'] >= 60
PY

grep -Fq 'ExecStart=/usr/bin/python3 /usr/local/lib/msfixit-shopos/ota-notify.py daemon' "$service"
grep -Fq 'ProtectSystem=strict' "$service"
grep -Fq 'ReadWritePaths=/var/lib/msfixit-shopos/update' "$service"
grep -Fq 'Wants=msfixit-ota-notify.service' "$boot_sync"
grep -Fq 'After=msfixit-ota-notify.service' "$boot_sync"

grep -Fq "[str(UPDATE_AGENT), 'run']" "$client"
grep -Fq "notification.get('action') != 'check'" "$client"
grep -Fq "nonce == state.get('last_notification_nonce')" "$client"
grep -Fq "parsed.scheme != 'https'" "$client"
grep -Fq "Authorization" "$client"

if grep -Eq 'subprocess\.(run|Popen).*notification|eval\(|exec\(' "$client"; then
  echo 'OTA notification client must never execute notification-provided content.' >&2
  exit 1
fi

printf 'PASS: OTA notification layer is HTTPS-only, replay-limited and only wakes the signed update agent.\n'
