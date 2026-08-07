#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent="$root/image/package/usr/local/sbin/msfixit-update-agent"
update="$root/image/package/usr/local/sbin/msfixit-update"
writer="$root/image/package/usr/local/sbin/msfixit-slot-writer"
python3 -m py_compile "$agent" "$update" "$writer"
python3 - "$agent" "$update" "$writer" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import sys
import tempfile
from datetime import datetime, timezone


def load(name, filename):
    path = pathlib.Path(filename)
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module

agent = load('shopos_update_agent', sys.argv[1])
update = load('shopos_update', sys.argv[2])
writer = load('shopos_slot_writer', sys.argv[3])

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
    loaded = agent.load_config(config)
    assert loaded['repository'] == 'Ms-FixIT-25/msfixit-shopos'

    bad = dict(loaded)
    bad['repository'] = 'attacker/repository'
    config.write_text(json.dumps(bad))
    try:
        agent.load_config(config)
    except agent.AgentError:
        pass
    else:
        raise AssertionError('foreign repository was accepted')

for good in (
    'https://api.github.com/repos/Ms-FixIT-25/msfixit-shopos/releases/latest',
    'https://github.com/Ms-FixIT-25/msfixit-shopos/releases/download/v1/rootfs.xz',
    'https://release-assets.githubusercontent.com/example',
):
    agent.validate_url(good)

for bad in (
    'http://github.com/file',
    'https://evil.example/file',
    'https://user:secret@github.com/file',
):
    try:
        agent.validate_url(bad)
    except agent.AgentError:
        pass
    else:
        raise AssertionError(f'unsafe URL was accepted: {bad}')

now = datetime(2026, 8, 7, 10, 0, 0, tzinfo=timezone.utc)
payload = {
    'schema': 1,
    'version': '1.2.3',
    'sequence': 12,
    'image_url': 'https://github.com/Ms-FixIT-25/msfixit-shopos/releases/download/v1/rootfs.xz',
    'image_sha256': 'a' * 64,
    'image_size': 4096,
    'target': 'rpi4-usb',
    'minimum_sequence': 0,
    'issued_at': '2026-08-07T09:50:00Z',
    'expires_at': '2026-08-08T09:50:00Z',
}
update.validate_payload(payload, now=now)

for field, value in (
    ('expires_at', '2026-08-07T09:59:59Z'),
    ('issued_at', '2026-08-07T10:11:00Z'),
):
    invalid = dict(payload)
    invalid[field] = value
    try:
        update.validate_payload(invalid, now=now)
    except update.UpdateError:
        pass
    else:
        raise AssertionError(f'invalid manifest time was accepted: {field}={value}')

invalid_order = dict(payload)
invalid_order['issued_at'] = '2026-08-08T10:00:00Z'
invalid_order['expires_at'] = '2026-08-08T09:00:00Z'
try:
    update.validate_payload(invalid_order, now=datetime(2026, 8, 8, 8, 0, tzinfo=timezone.utc))
except update.UpdateError:
    pass
else:
    raise AssertionError('manifest expiry before issue time was accepted')

agent_source = pathlib.Path(sys.argv[1]).read_text()
write_call = "run([str(WRITER), 'write'"
stage_call = "run([str(UPDATE), '--state', str(STATE), 'stage'"
assert write_call in agent_source and stage_call in agent_source
assert agent_source.index(write_call) < agent_source.index(stage_call), 'persistent stage state is opened before slot write'
assert 'exclusive_update_lock' in agent_source
assert "'abort-stage'" in agent_source

update_source = pathlib.Path(sys.argv[2]).read_text()
assert 'manifest has expired' in update_source
assert 'manifest issue time is in the future' in update_source
assert 'abort-stage' in update_source

with tempfile.TemporaryDirectory() as temp:
    target = pathlib.Path(temp) / 'slot.img'
    target.write_bytes(b'\0' * 1024)
    os.environ['SHOPOS_SLOT_WRITER_TEST'] = '1'
    assert writer.target_capacity(target) == 1024
    writer.ensure_capacity(target, 1024)
    try:
        writer.ensure_capacity(target, 1025)
    except writer.SlotError:
        pass
    else:
        raise AssertionError('oversized image was not rejected before writing')

print('ShopOS update-agent freshness, trust-boundary and transaction-safety tests passed')
PY
