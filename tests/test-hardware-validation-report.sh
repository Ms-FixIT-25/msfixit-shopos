#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
reporter="$root/scripts/hardware-validation-report.py"
python3 -m py_compile "$reporter"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'ShopOS test image\n' > "$tmp/image.img"
cat > "$tmp/results.json" <<'JSON'
[
  {"test":"boot-slot-a","result":"pass","notes":"Booted from SHOPOS_ROOT_A."},
  {"test":"boot-slot-b","result":"pass","notes":"Booted from SHOPOS_ROOT_B."},
  {"test":"power-loss-update","result":"blocked","notes":"Requires switched power fixture."}
]
JSON
python3 "$reporter" \
  --image "$tmp/image.img" \
  --commit 0123456789abcdef0123456789abcdef01234567 \
  --device-id pi4-lab-01 \
  --results "$tmp/results.json" \
  --output "$tmp/report.json"
python3 - "$tmp/report.json" <<'PY'
import json, pathlib, sys
report = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert report['schema'] == 1
assert report['image']['commit'] == '0123456789abcdef0123456789abcdef01234567'
assert len(report['image']['sha256']) == 64
assert report['summary'] == {'pass': 2, 'fail': 0, 'blocked': 1}
assert report['device']['id'] == 'pi4-lab-01'
PY
cat > "$tmp/bad.json" <<'JSON'
[{"test":"arbitrary-command","result":"pass","notes":"must fail"}]
JSON
if python3 "$reporter" --image "$tmp/image.img" --commit 0123456789abcdef0123456789abcdef01234567 --device-id pi4-lab-01 --results "$tmp/bad.json" --output "$tmp/bad-report.json"; then
  echo 'invalid test was accepted' >&2
  exit 1
fi
echo 'PASS: hardware reports bind image, commit, device and constrained results.'
