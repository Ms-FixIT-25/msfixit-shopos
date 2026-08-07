#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$root/scripts/validate-shopos-app.py"
example="$root/examples/apps/example/manifest.json"

python3 -m py_compile "$validator"
python3 "$validator" "$example"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 - "$example" "$tmp" <<'PY'
import json, pathlib, sys
source = json.loads(pathlib.Path(sys.argv[1]).read_text())
out = pathlib.Path(sys.argv[2])
for name, mutate in {
    "unknown": lambda d: d.update({"shell": "/bin/sh"}),
    "edition": lambda d: d.update({"edition": "master"}),
    "capability": lambda d: d.update({"capabilities": ["unrestricted-shell"]}),
    "entrypoint": lambda d: d.update({"entrypoints": {"admin": "/apps/../root/"}}),
}.items():
    data = json.loads(json.dumps(source))
    mutate(data)
    (out / f"{name}.json").write_text(json.dumps(data))
PY

for invalid in "$tmp"/*.json; do
    if python3 "$validator" "$invalid"; then
        echo "Invalid manifest accepted: $invalid" >&2
        exit 1
    fi
done

grep -Fq 'There is no hard-coded universal bypass or plaintext master key' "$root/docs/SHOPOS_PLATFORM.md"
grep -Fq 'Community remains useful' "$root/docs/SHOPOS_PLATFORM.md"
! grep -RniE '(MASTER_KEY|PRIVATE_KEY)[[:space:]]*=' "$root/image" "$root/scripts" "$root/examples" 2>/dev/null

printf 'PASS: ShopOS Core/App boundary, strict manifest validation and no embedded master bypass.\n'
