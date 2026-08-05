#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/scripts/shopos-app-install.py"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 -m py_compile "$installer"
openssl genpkey -algorithm ED25519 -out "$tmp/private.pem" >/dev/null 2>&1
openssl pkey -in "$tmp/private.pem" -pubout -out "$tmp/public.pem" >/dev/null 2>&1
mkdir -p "$tmp/pkg/payload" "$tmp/apps" "$tmp/log"
printf 'hello\n' > "$tmp/pkg/payload/index.txt"
cp "$root/examples/apps/example/manifest.json" "$tmp/pkg/manifest.json"
tar -C "$tmp/pkg/payload" -cf "$tmp/pkg/payload.tar" .
python3 - "$tmp/pkg" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1])
d=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
meta={"schema":1,"app_id":"at.msfixit.shopos.example","version":"1.0.0","manifest_sha256":d(p/'manifest.json'),"payload_sha256":d(p/'payload.tar'),"signature":"pending"}
(p/'package.json').write_text(json.dumps(meta,sort_keys=True,separators=(',',':')))
PY
python3 - "$tmp/pkg/package.json" "$tmp/payload" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d.pop('signature'); pathlib.Path(sys.argv[2]).write_text(json.dumps(d,sort_keys=True,separators=(',',':')))
PY
openssl pkeyutl -sign -inkey "$tmp/private.pem" -rawin -in "$tmp/payload" -out "$tmp/sig"
python3 - "$tmp/pkg/package.json" "$tmp/sig" <<'PY'
import base64,json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['signature']=base64.b64encode(pathlib.Path(sys.argv[2]).read_bytes()).decode(); p.write_text(json.dumps(d))
PY
tar -C "$tmp/pkg" -czf "$tmp/app.shopos" package.json manifest.json payload.tar
python3 "$installer" "$tmp/app.shopos" --public-key "$tmp/public.pem" --root "$tmp/apps" --audit "$tmp/log/audit.jsonl"
test -f "$tmp/apps/at.msfixit.shopos.example/index.txt"
grep -Fq '"result": "success"' "$tmp/log/audit.jsonl"
cp "$tmp/app.shopos" "$tmp/tampered.shopos"
printf x >> "$tmp/tampered.shopos"
! python3 "$installer" "$tmp/tampered.shopos" --public-key "$tmp/public.pem" --root "$tmp/apps" --audit "$tmp/log/audit.jsonl"
mkdir -p "$tmp/existing/at.msfixit.shopos.example"; printf old > "$tmp/existing/at.msfixit.shopos.example/old.txt"
! python3 "$installer" "$tmp/app.shopos" --public-key "$tmp/public.pem" --root "$tmp/existing" --audit "$tmp/log/audit2.jsonl" --fail-after-stage
test -f "$tmp/existing/at.msfixit.shopos.example/old.txt"
! grep -R -E '(PRIVATE KEY|master[_ -]?key|universal bypass)' "$installer"
printf 'PASS: signed app packages verify hashes and signatures, reject tampering and preserve existing installs on staged failure.\n'
