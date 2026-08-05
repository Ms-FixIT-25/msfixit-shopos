#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
writer="$root/image/package/usr/local/sbin/msfixit-slot-writer"
python3 -m py_compile "$writer"
grep -Fq "SHOPOS_ROOT_A" "$root/image/package/etc/msfixit-shopos/update-slots.json"
grep -Fq "SHOPOS_ROOT_B" "$root/image/package/etc/msfixit-shopos/update-slots.json"
! grep -Eq '(shell=True|os\.system|subprocess\.(run|Popen))' "$writer"
python3 - "$writer" <<'PY'
import hashlib, importlib.util, os, pathlib, tempfile
path = pathlib.Path(__import__('sys').argv[1])
spec = importlib.util.spec_from_file_location('slot_writer', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    image = root / 'image.bin'
    target = root / 'slot-b.bin'
    boot = root / 'boot' / 'shopos-slot.env'
    payload = (b'ShopOS-slot-test\0' * 65536)
    image.write_bytes(payload)
    target.write_bytes(b'\0' * (len(payload) + 4096))
    os.environ['SHOPOS_SLOT_WRITER_TEST'] = '1'
    cfg = {'slots': {'A': str(root/'slot-a.bin'), 'B': str(target)}, 'boot_selection': str(boot)}
    digest = hashlib.sha256(payload).hexdigest()
    module.write_slot(cfg, 'B', image, digest, len(payload))
    assert target.read_bytes()[:len(payload)] == payload
    module.select_slot(cfg, 'B')
    assert boot.read_text() == 'SHOPOS_SLOT=B\nSHOPOS_ROOT_LABEL=SHOPOS_ROOT_B\n'
    try:
        module.write_slot(cfg, 'B', image, '0'*64, len(payload))
    except module.SlotError:
        pass
    else:
        raise AssertionError('bad digest accepted')
print('PASS: constrained slot writing, read-back verification and atomic boot selection work.')
PY
