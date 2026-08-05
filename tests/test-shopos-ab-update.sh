#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

private="$work/private.pem"
public="$work/public.pem"
image="$work/shopos.img"
manifest="$work/manifest.json"
state="$work/state.json"
payload="$work/payload.json"
signature="$work/signature.bin"

openssl genpkey -algorithm Ed25519 -out "$private" >/dev/null 2>&1
openssl pkey -in "$private" -pubout -out "$public" >/dev/null 2>&1
printf 'verified ShopOS image payload\n' > "$image"
digest="$(sha256sum "$image" | awk '{print $1}')"
size="$(stat -c '%s' "$image")"

python3 - "$payload" "$digest" "$size" <<'PY'
import json, pathlib, sys
path, digest, size = pathlib.Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
payload = {
    "expires_at": "2099-01-01T00:00:00Z",
    "image_sha256": digest,
    "image_size": size,
    "image_url": "https://updates.example.invalid/shopos.img",
    "issued_at": "2026-08-05T00:00:00Z",
    "minimum_sequence": 0,
    "schema": 1,
    "sequence": 1,
    "target": "rpi4-usb",
    "version": "0.11.0",
}
path.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
PY
openssl pkeyutl -sign -inkey "$private" -rawin -in "$payload" -out "$signature"
python3 - "$payload" "$signature" "$manifest" <<'PY'
import base64, json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
signature = base64.b64encode(pathlib.Path(sys.argv[2]).read_bytes()).decode("ascii")
pathlib.Path(sys.argv[3]).write_text(json.dumps({"payload": payload, "signature": signature}), encoding="utf-8")
PY

runtime=(python3 "$root/scripts/shopos-update.py" --state "$state" --public-key "$public")
"${runtime[@]}" verify "$manifest" --image "$image" >/dev/null
"${runtime[@]}" stage "$manifest" | grep -q '"target_slot": "B"'
"${runtime[@]}" activate-trial | grep -q '"active_slot": "B"'
"${runtime[@]}" record-boot >/dev/null
"${runtime[@]}" record-boot >/dev/null
"${runtime[@]}" record-boot | grep -q '"state": "rollback"'
"${runtime[@]}" status | grep -q '"active_slot": "A"'
"${runtime[@]}" reset-rollback | grep -q '"state": "idle"'

"${runtime[@]}" stage "$manifest" >/dev/null
"${runtime[@]}" activate-trial >/dev/null
"${runtime[@]}" confirm | grep -q '"installed_sequence": 1'
if "${runtime[@]}" stage "$manifest" >/dev/null 2>&1; then
    echo 'Replay of an installed update was accepted.' >&2
    exit 1
fi

python3 - "$manifest" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["payload"]["sequence"] = 2
path.write_text(json.dumps(data))
PY
if "${runtime[@]}" verify "$manifest" >/dev/null 2>&1; then
    echo 'Tampered manifest was accepted.' >&2
    exit 1
fi

printf 'PASS: signed A/B update manifests, replay protection, trial confirmation and automatic rollback work fail-closed.\n'
