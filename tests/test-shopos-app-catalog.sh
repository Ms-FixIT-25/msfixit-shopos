#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$root/scripts/shopos-app-catalog.py"
catalog="$root/catalog/apps.json"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 -m py_compile "$resolver"
python3 "$resolver" "$catalog" > "$tmp/community.json"
grep -Fq '"action": "unlock"' "$tmp/community.json"
cat > "$tmp/pro.json" <<'JSON'
{"valid":true,"edition":"professional","entitlements":["commerce.core","marketplaces.connect","assistant.use"]}
JSON
python3 "$resolver" "$catalog" --license-json "$tmp/pro.json" > "$tmp/pro-result.json"
[ "$(grep -o '"action": "install"' "$tmp/pro-result.json" | wc -l)" -eq 3 ]
cp "$catalog" "$tmp/bad.json"
python3 - "$tmp/bad.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d["schema"]=2; p.write_text(json.dumps(d))
PY
! python3 "$resolver" "$tmp/bad.json"
printf 'PASS: app catalog resolves locked and installable states fail-closed.\n'
