#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

find "$repo_root/scripts" "$repo_root/image/assets/usr/local/sbin" \
    -type f -print0 |
    while IFS= read -r -d '' script; do
        bash -n "$script"
    done

python3 - "$repo_root" <<'PY'
from pathlib import Path
import sys
import yaml

root = Path(sys.argv[1])
for path in [
    root / "image/config/shopos-rpi5.yaml",
    root / "image/layer/msfixit-shopos.yaml",
    root / ".github/workflows/build-image.yml",
]:
    with path.open("r", encoding="utf-8") as handle:
        yaml.safe_load(handle)
print("YAML and shell syntax checks passed.")
PY
