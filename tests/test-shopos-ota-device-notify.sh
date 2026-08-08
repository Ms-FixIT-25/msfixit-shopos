#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)";client="$root/image/package/usr/local/lib/msfixit-shopos/ota-notify.py";service="$root/image/package/etc/systemd/system/msfixit-ota-notify.service";boot_sync="$root/image/package/etc/systemd/system/msfixit-update-boot-sync.service";config="$root/image/package/etc/msfixit-shopos/ota-notify.json"
python3 -m py_compile "$client";python3 "$client" --self-test
python3 - <<PY
import ast
import json
from pathlib import Path
c=json.loads(Path('$config').read_text());assert c['schema']==1 and c['enabled'] is False and c['endpoint']=='' and c['channel']=='stable';assert 10<=c['long_poll_seconds']<=120 and c['minimum_wake_interval_seconds']>=60
source=Path('$client').read_text()
tree=ast.parse(source)
# The notification path may only wake the fixed local signed updater command.
run_calls=[]
for node in ast.walk(tree):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name) and node.func.value.id=='subprocess' and node.func.attr in {'run','Popen'}:
        run_calls.append(node)
assert len(run_calls)==1, f'unexpected subprocess call count: {len(run_calls)}'
call=run_calls[0]
assert isinstance(call.func, ast.Attribute) and call.func.attr=='run'
assert call.args and isinstance(call.args[0], ast.List) and len(call.args[0].elts)==2
second=call.args[0].elts[1]
assert isinstance(second, ast.Constant) and second.value=='run'
assert not any(isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in {'eval','exec'} for n in ast.walk(tree))
PY
grep -Fq 'ExecStart=/usr/bin/python3 /usr/local/lib/msfixit-shopos/ota-notify.py daemon' "$service"
grep -Fq 'ProtectSystem=strict' "$service";grep -Fq 'ReadWritePaths=/var/lib/msfixit-shopos/update' "$service";grep -Fq 'Wants=msfixit-ota-notify.service' "$boot_sync";grep -Fq 'After=msfixit-ota-notify.service' "$boot_sync"
grep -Fq "[str(UPDATE_AGENT),'run']" "$client";grep -Fq "n.get('action')=='check'" "$client";grep -Fq "nonce!=s.get('last_notification_nonce')" "$client";grep -Fq "p.scheme!='https'" "$client";grep -Fq 'Authorization' "$client";grep -Fq "report(c,s,'heartbeat'" "$client";grep -Fq "report(c,s,'result'" "$client"
printf 'PASS: OTA notification layer is HTTPS-only, replay-limited, reports status and only wakes the signed update agent.\n'
