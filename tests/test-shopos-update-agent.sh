#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent="$root/image/package/usr/local/sbin/msfixit-update-agent"
python3 -m py_compile "$agent"
python3 - "$agent" <<'PY'
import importlib.machinery
import importlib.util
import json
import pathlib
import sys
import tempfile

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader('shopos_update_agent', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

with tempfile.TemporaryDirectory() as temp:
    config = pathlib.Path(temp) / 'config.json'
    config.write_text(json.dumps({
        'schema': 1,
        'repository': 'Ms-FixIT-25/msfixit-shopos',
        'channel': 'stable',
        'manifest_asset': 'shopos-update-manifest.json',
        'auto_apply': False,
        'reboot_after_apply': True,
    }))
    loaded = module.load_config(config)
    assert loaded['repository'] == 'Ms-FixIT-25/msfixit-shopos'

    bad = dict(loaded)
    bad['repository'] = 'attacker/repository'
    config.write_text(json.dumps(bad))
    try:
        module.load_config(config)
    except module.AgentError:
        pass
    else:
        raise AssertionError('foreign repository was accepted')

for good in (
    'https://api.github.com/repos/Ms-FixIT-25/msfixit-shopos/releases/latest',
    'https://github.com/Ms-FixIT-25/msfixit-shopos/releases/download/v1/rootfs.xz',
    'https://release-assets.githubusercontent.com/example',
):
    module.validate_url(good)

for bad in (
    'http://github.com/file',
    'https://evil.example/file',
    'https://user:secret@github.com/file',
):
    try:
        module.validate_url(bad)
    except module.AgentError:
        pass
    else:
        raise AssertionError(f'unsafe URL was accepted: {bad}')

print('ShopOS update-agent trust-boundary tests passed')
PY
