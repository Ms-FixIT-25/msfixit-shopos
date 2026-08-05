#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="$root/scripts/shopos-license.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 -m py_compile "$verifier"
openssl genpkey -algorithm ED25519 -out "$tmp/private.pem" >/dev/null 2>&1
openssl pkey -in "$tmp/private.pem" -pubout -out "$tmp/public.pem" >/dev/null 2>&1

make_license() {
  local output="$1" edition="$2" developer="$3" expires="$4"
  python3 - "$output" "$edition" "$developer" "$expires" <<'PY'
import json, pathlib, sys
path, edition, developer, expires = sys.argv[1:]
data = {
  "schema": 1,
  "license_id": "test-license-001",
  "customer_id": "test-customer",
  "edition": edition,
  "entitlements": ["apps.install", "commerce.automation"],
  "issued_at": "2026-01-01T00:00:00Z",
  "expires_at": None if expires == "none" else expires,
  "installations": 1,
  "developer": developer == "true",
  "signature": "pending"
}
pathlib.Path(path).write_text(json.dumps(data, indent=2), encoding="utf-8")
PY
  python3 - "$output" "$tmp/payload" <<'PY'
import json, pathlib, sys
source = json.loads(pathlib.Path(sys.argv[1]).read_text())
source.pop("signature")
pathlib.Path(sys.argv[2]).write_text(json.dumps(source, sort_keys=True, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
PY
  openssl pkeyutl -sign -inkey "$tmp/private.pem" -rawin -in "$tmp/payload" -out "$tmp/signature.bin"
  python3 - "$output" "$tmp/signature.bin" <<'PY'
import base64, json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["signature"] = base64.b64encode(pathlib.Path(sys.argv[2]).read_bytes()).decode()
path.write_text(json.dumps(data, indent=2), encoding="utf-8")
PY
}

make_license "$tmp/pro.json" professional false none
python3 "$verifier" "$tmp/pro.json" --public-key "$tmp/public.pem" --require-entitlement commerce.automation --json | grep -Fq '"valid": true'

cp "$tmp/pro.json" "$tmp/tampered.json"
python3 - "$tmp/tampered.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["edition"]="enterprise"; p.write_text(json.dumps(d))
PY
! python3 "$verifier" "$tmp/tampered.json" --public-key "$tmp/public.pem"

make_license "$tmp/expired.json" professional false 2026-02-01T00:00:00Z
! python3 "$verifier" "$tmp/expired.json" --public-key "$tmp/public.pem"

make_license "$tmp/dev.json" developer true none
python3 "$verifier" "$tmp/dev.json" --public-key "$tmp/public.pem" --json | grep -Fq '"developer": true'

cp "$tmp/pro.json" "$tmp/unknown.json"
python3 - "$tmp/unknown.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["master_key"]="forbidden"; p.write_text(json.dumps(d))
PY
! python3 "$verifier" "$tmp/unknown.json" --public-key "$tmp/public.pem"

! grep -R -E '(PRIVATE KEY|master[_ -]?key|universal bypass)' "$root/scripts/shopos-license.py" "$root/examples/apps" 2>/dev/null
printf 'PASS: signed license runtime rejects tampering, expiry, unknown fields and missing entitlements.\n'
