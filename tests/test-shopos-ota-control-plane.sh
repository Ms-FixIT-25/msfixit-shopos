#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
server="$root/ota/control-plane/shopos_ota_control.py"
python3 -m py_compile "$server"
python3 - "$server" <<'PY'
import importlib.util,pathlib,tempfile,time,sys
p=pathlib.Path(sys.argv[1]);s=importlib.util.spec_from_file_location('ota',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
with tempfile.TemporaryDirectory() as d:
 db=f'{d}/ota.sqlite3';m.init_db(db)
 with m.connect(db) as c:
  tables={r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")};assert {'devices','notifications'}<=tables
  cols={r[1] for r in c.execute('PRAGMA table_info(devices)')};assert 'last_notification_id' in cols
 good={'schema':1,'device_id':'d','client_instance':'i','architecture':'aarch64','shopos_version':'1','channel':'stable'};m.validate_registration(good)
 try:m.validate_registration({**good,'channel':'evil'})
 except ValueError:pass
 else:raise AssertionError('invalid channel accepted')
 token='x'*40;assert m.token_hash(token)!=token
print('PASS: OTA control-plane schema, channel guards and notification cursor')
PY
grep -Fq "action':'check" "$server"
grep -Fq 'last_notification_id' "$server"
grep -Fq 'SHOPOS_OTA_ADMIN_TOKEN' "$server"
grep -Fq 'hmac.compare_digest' "$server"
! grep -Eq 'eval\(|exec\(|shell=True' "$server"
echo 'PASS: OTA control plane keeps notification payload non-executable and authentication explicit.'
