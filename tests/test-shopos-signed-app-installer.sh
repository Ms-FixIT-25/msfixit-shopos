#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/image/package/usr/lib/msfixit-shopos/shopos-app-install.py"
validator="$root/image/package/usr/lib/msfixit-shopos/validate-shopos-app.py"
source_installer="$root/scripts/shopos-app-install.py"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

test -s "$installer"
test -s "$validator"
python3 -m py_compile "$installer" "$validator" "$source_installer"
grep -Fq 'signed app_id does not match manifest id' "$installer"
grep -Fq 'signed version does not match manifest version' "$installer"
grep -Fq 'unsupported archive member type' "$installer"
grep -Fq 'set-id archive member is forbidden' "$installer"

openssl genpkey -algorithm ED25519 -out "$tmp/private.pem" >/dev/null 2>&1
openssl pkey -in "$tmp/private.pem" -pubout -out "$tmp/public.pem" >/dev/null 2>&1
mkdir -p "$tmp/pkg/payload" "$tmp/apps" "$tmp/log"
printf 'hello\n' > "$tmp/pkg/payload/index.txt"
cp "$root/examples/apps/example/manifest.json" "$tmp/pkg/manifest.json"
tar -C "$tmp/pkg/payload" -cf "$tmp/pkg/payload.tar" .

sign_package() {
    local pkg_dir="$1" app_id="$2" version="$3" output="$4"
    python3 - "$pkg_dir" "$app_id" "$version" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1])
d=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
meta={"schema":1,"app_id":sys.argv[2],"version":sys.argv[3],"manifest_sha256":d(p/'manifest.json'),"payload_sha256":d(p/'payload.tar'),"signature":"pending"}
(p/'package.json').write_text(json.dumps(meta,sort_keys=True,separators=(',',':')))
PY
    python3 - "$pkg_dir/package.json" "$tmp/signing-payload" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d.pop('signature'); pathlib.Path(sys.argv[2]).write_text(json.dumps(d,sort_keys=True,separators=(',',':')))
PY
    openssl pkeyutl -sign -inkey "$tmp/private.pem" -rawin -in "$tmp/signing-payload" -out "$tmp/sig"
    python3 - "$pkg_dir/package.json" "$tmp/sig" <<'PY'
import base64,json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['signature']=base64.b64encode(pathlib.Path(sys.argv[2]).read_bytes()).decode(); p.write_text(json.dumps(d))
PY
    tar -C "$pkg_dir" -czf "$output" package.json manifest.json payload.tar
}

sign_package "$tmp/pkg" at.msfixit.shopos.example 1.0.0 "$tmp/app.shopos"
python3 "$installer" "$tmp/app.shopos" --public-key "$tmp/public.pem" --root "$tmp/apps" --audit "$tmp/log/audit.jsonl"
test -f "$tmp/apps/at.msfixit.shopos.example/index.txt"
grep -Fq '"result": "success"' "$tmp/log/audit.jsonl"

# A valid signature must not allow the signed package identity to disagree with
# the separately hashed manifest identity.
cp -a "$tmp/pkg" "$tmp/mismatch"
python3 - "$tmp/mismatch/manifest.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['id']='at.msfixit.shopos.other'; p.write_text(json.dumps(d))
PY
sign_package "$tmp/mismatch" at.msfixit.shopos.example 1.0.0 "$tmp/mismatch.shopos"
! python3 "$installer" "$tmp/mismatch.shopos" --public-key "$tmp/public.pem" --root "$tmp/apps" --audit "$tmp/log/mismatch.jsonl"

cp -a "$tmp/pkg" "$tmp/version-mismatch"
python3 - "$tmp/version-mismatch/manifest.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()); d['version']='9.9.9'; p.write_text(json.dumps(d))
PY
sign_package "$tmp/version-mismatch" at.msfixit.shopos.example 1.0.0 "$tmp/version-mismatch.shopos"
! python3 "$installer" "$tmp/version-mismatch.shopos" --public-key "$tmp/public.pem" --root "$tmp/apps" --audit "$tmp/log/version-mismatch.jsonl"

# Root extraction must reject special tar members even when they appear in the
# outer package archive.
python3 - "$tmp/app.shopos" "$tmp/special.shopos" <<'PY'
import io,tarfile,sys
source=tarfile.open(sys.argv[1],'r:gz')
with tarfile.open(sys.argv[2],'w:gz') as out:
    for member in source.getmembers():
        fileobj=source.extractfile(member) if member.isfile() else None
        out.addfile(member,fileobj)
    fifo=tarfile.TarInfo('unexpected-fifo')
    fifo.type=tarfile.FIFOTYPE
    fifo.mode=0o600
    out.addfile(fifo)
source.close()
PY
! python3 "$installer" "$tmp/special.shopos" --public-key "$tmp/public.pem" --root "$tmp/apps" --audit "$tmp/log/special.jsonl"

mkdir -p "$tmp/existing/at.msfixit.shopos.example"; printf old > "$tmp/existing/at.msfixit.shopos.example/old.txt"
! python3 "$installer" "$tmp/app.shopos" --public-key "$tmp/public.pem" --root "$tmp/existing" --audit "$tmp/log/audit2.jsonl" --fail-after-stage
test -f "$tmp/existing/at.msfixit.shopos.example/old.txt"
! grep -R -E '(PRIVATE KEY|master[_ -]?key|universal bypass)' "$installer" "$validator"
printf 'PASS: packaged signed app runtime verifies signatures, binds manifest identity, rejects unsafe archives and preserves rollback state.\n'
