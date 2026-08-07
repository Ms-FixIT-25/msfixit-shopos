#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
layout="$root/scripts/postprocess-ab-image.sh"
selector="$root/image/package/usr/local/sbin/msfixit-boot-selector"
syncer="$root/image/package/usr/local/sbin/msfixit-update-boot-sync"

bash -n "$layout"
python3 -m py_compile "$selector"
bash -n "$syncer"
grep -Fq 'SHOPOS_ROOT_A' "$layout"
grep -Fq 'SHOPOS_ROOT_B' "$layout"
grep -Fq 'expected exactly boot and root partitions' "$layout"
grep -Fq 'dd if="$root_a" of="$root_b"' "$layout"
grep -Fq "root=LABEL=" "$selector"
grep -Fq "tokens[roots[0]] = 'root=LABEL=SHOPOS_ROOT_A'" "$layout"
grep -Fq "tokens = [token for token in tokens if not token.startswith('consoleblank=')]" "$layout"
grep -Fq "tokens.append('consoleblank=0')" "$layout"
grep -Fq 'initial_root=LABEL=SHOPOS_ROOT_A' "$layout"
! grep -Fq '/dev/disk/by-slot/system' "$layout"
! grep -Eq '(shell=True|os\.system|subprocess\.)' "$selector"

python3 - "$selector" <<'PY'
import importlib.machinery, importlib.util, os, pathlib, sys, tempfile
path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader('boot_selector', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
with tempfile.TemporaryDirectory() as tmp:
    cmdline = pathlib.Path(tmp) / 'cmdline.txt'
    cmdline.write_text('console=serial0,115200 root=PARTUUID=deadbeef-02 rootfstype=ext4 rw quiet consoleblank=0\n')
    os.environ['SHOPOS_BOOT_SELECTOR_TEST'] = '1'
    module.select('B', cmdline)
    value = cmdline.read_text()
    assert 'root=LABEL=SHOPOS_ROOT_B' in value
    assert 'PARTUUID=deadbeef-02' not in value
    assert value.split().count('consoleblank=0') == 1
    module.select('A', cmdline)
    value = cmdline.read_text()
    assert 'root=LABEL=SHOPOS_ROOT_A' in value
    assert value.split().count('consoleblank=0') == 1
print('PASS: A/B image layout selects Slot A initially, enforces consoleblank=0 and preserves it across atomic A/B kernel root switching.')
PY
