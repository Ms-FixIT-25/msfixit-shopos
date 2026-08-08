#!/usr/bin/env python3
"""ShopOS OTA notification client.

The notification plane never supplies executable content. It only tells the local
signed update agent to perform its normal verified update check. The existing
ShopOS update agent remains the authority for release, manifest, checksum and A/B
installation decisions.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import platform
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from typing import Any

CONFIG = pathlib.Path('/etc/msfixit-shopos/ota-notify.json')
STATE = pathlib.Path('/var/lib/msfixit-shopos/update/device-notify.json')
VERSION_FILE = pathlib.Path('/usr/share/msfixit-shopos/build-info.txt')
UPDATE_AGENT = pathlib.Path('/usr/local/sbin/msfixit-update-agent')
MAX_RESPONSE = 256 * 1024
ALLOWED_CONFIG_KEYS = {
    'schema', 'enabled', 'endpoint', 'channel', 'long_poll_seconds',
    'retry_min_seconds', 'retry_max_seconds', 'minimum_wake_interval_seconds',
}


class NotifyError(RuntimeError):
    pass


def load_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise NotifyError(f'cannot read valid JSON: {path}') from exc
    if not isinstance(value, dict):
        raise NotifyError('JSON document must be an object')
    return value


def load_config(path: pathlib.Path) -> dict[str, Any]:
    cfg = load_json(path)
    if set(cfg) != ALLOWED_CONFIG_KEYS or cfg.get('schema') != 1:
        raise NotifyError('OTA notification configuration does not match strict schema')
    if not isinstance(cfg.get('enabled'), bool):
        raise NotifyError('enabled must be boolean')
    if cfg.get('channel') not in {'stable', 'candidate'}:
        raise NotifyError('unsupported OTA notification channel')
    endpoint = cfg.get('endpoint')
    if not isinstance(endpoint, str):
        raise NotifyError('endpoint must be a string')
    if cfg['enabled']:
        validate_endpoint(endpoint)
    for key in ('long_poll_seconds', 'retry_min_seconds', 'retry_max_seconds', 'minimum_wake_interval_seconds'):
        if not isinstance(cfg.get(key), int) or cfg[key] < 1:
            raise NotifyError(f'{key} must be a positive integer')
    if not 10 <= cfg['long_poll_seconds'] <= 120:
        raise NotifyError('long_poll_seconds must be between 10 and 120')
    if cfg['retry_min_seconds'] > cfg['retry_max_seconds']:
        raise NotifyError('retry interval is invalid')
    return cfg


def validate_endpoint(endpoint: str) -> None:
    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise NotifyError('OTA notification endpoint must be an HTTPS origin without embedded credentials')
    if parsed.query or parsed.fragment:
        raise NotifyError('OTA notification endpoint must not contain query or fragment data')


def same_https_origin(requested: str, final: str) -> bool:
    requested_url = urllib.parse.urlparse(requested)
    final_url = urllib.parse.urlparse(final)
    return (
        requested_url.scheme == 'https'
        and final_url.scheme == 'https'
        and requested_url.hostname == final_url.hostname
        and (requested_url.port or 443) == (final_url.port or 443)
    )


def atomic_write_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.new')
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, 'O_NOFOLLOW'):
        flags |= os.O_NOFOLLOW
    fd = os.open(temp, flags, 0o600)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(value, handle, sort_keys=True)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)
        os.chmod(path, 0o600)
    finally:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass


def read_version() -> str:
    try:
        for line in VERSION_FILE.read_text(encoding='utf-8').splitlines():
            if line.startswith('SHOPOS_VERSION='):
                return line.split('=', 1)[1].strip() or 'unknown'
    except OSError:
        pass
    return 'unknown'


def initial_state() -> dict[str, Any]:
    return {
        'schema': 1,
        'device_id': str(uuid.uuid4()),
        'registration_token': None,
        'last_notification_nonce': None,
        'last_wake_epoch': 0,
        'client_instance': secrets.token_hex(16),
    }


def load_or_create_state(path: pathlib.Path) -> dict[str, Any]:
    if not path.exists():
        state = initial_state()
        atomic_write_json(path, state)
        return state
    state = load_json(path)
    expected = {'schema', 'device_id', 'registration_token', 'last_notification_nonce', 'last_wake_epoch', 'client_instance'}
    if set(state) != expected or state.get('schema') != 1:
        raise NotifyError('OTA notification state does not match strict schema')
    try:
        uuid.UUID(str(state['device_id']))
    except (ValueError, TypeError) as exc:
        raise NotifyError('device_id is invalid') from exc
    token = state.get('registration_token')
    if token is not None and (not isinstance(token, str) or len(token) < 32):
        raise NotifyError('registration token is invalid')
    if not isinstance(state.get('last_wake_epoch'), int):
        raise NotifyError('last_wake_epoch is invalid')
    return state


def endpoint_url(base: str, suffix: str) -> str:
    validate_endpoint(base)
    return base.rstrip('/') + suffix


def request_json(url: str, *, method: str = 'GET', payload: dict[str, Any] | None = None,
                 token: str | None = None, timeout: int = 30) -> dict[str, Any]:
    body = None
    headers = {'Accept': 'application/json', 'User-Agent': 'ShopOS-OTA-Notify/1'}
    if payload is not None:
        body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
        headers['Content-Type'] = 'application/json'
    if token:
        headers['Authorization'] = f'Bearer {token}'
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            final = response.geturl()
            if not same_https_origin(url, final):
                raise NotifyError('OTA notification request redirected outside its configured HTTPS origin')
            raw = response.read(MAX_RESPONSE + 1)
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        raise NotifyError('OTA notification request failed') from exc
    if len(raw) > MAX_RESPONSE:
        raise NotifyError('OTA notification response exceeds size limit')
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise NotifyError('OTA notification response is not valid JSON') from exc
    if not isinstance(value, dict):
        raise NotifyError('OTA notification response must be an object')
    return value


def register(cfg: dict[str, Any], state: dict[str, Any]) -> dict[str, Any]:
    if state.get('registration_token'):
        return state
    payload = {
        'schema': 1,
        'device_id': state['device_id'],
        'client_instance': state['client_instance'],
        'architecture': platform.machine(),
        'shopos_version': read_version(),
        'channel': cfg['channel'],
    }
    response = request_json(endpoint_url(cfg['endpoint'], '/v1/devices/register'), method='POST', payload=payload)
    token = response.get('token')
    if not isinstance(token, str) or len(token) < 32:
        raise NotifyError('registration response did not contain a valid device token')
    state['registration_token'] = token
    atomic_write_json(STATE, state)
    return state


def should_wake(state: dict[str, Any], notification: dict[str, Any], minimum_interval: int, now: int) -> bool:
    if notification.get('schema') != 1 or notification.get('action') != 'check':
        return False
    nonce = notification.get('nonce')
    if not isinstance(nonce, str) or len(nonce) < 16 or len(nonce) > 256:
        return False
    if nonce == state.get('last_notification_nonce'):
        return False
    if now - int(state.get('last_wake_epoch') or 0) < minimum_interval:
        return False
    return True


def wake_update_agent(state: dict[str, Any], nonce: str) -> None:
    result = subprocess.run(
        [str(UPDATE_AGENT), 'run'],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=3600,
        check=False,
    )
    now = int(time.time())
    state['last_notification_nonce'] = nonce
    state['last_wake_epoch'] = now
    atomic_write_json(STATE, state)
    if result.returncode != 0:
        raise NotifyError(result.stderr.strip() or 'signed update agent failed after notification wake')


def poll_once(cfg: dict[str, Any], state: dict[str, Any]) -> bool:
    token = state.get('registration_token')
    if not isinstance(token, str):
        raise NotifyError('device is not registered')
    device_id = urllib.parse.quote(str(state['device_id']), safe='')
    url = endpoint_url(cfg['endpoint'], f"/v1/devices/{device_id}/notifications?wait={cfg['long_poll_seconds']}")
    notification = request_json(url, token=token, timeout=cfg['long_poll_seconds'] + 10)
    now = int(time.time())
    if not should_wake(state, notification, cfg['minimum_wake_interval_seconds'], now):
        return False
    wake_update_agent(state, str(notification['nonce']))
    return True


def daemon(cfg: dict[str, Any]) -> int:
    if not cfg['enabled']:
        print('OTA notification client disabled; signed GitHub polling fallback remains active.')
        return 0
    state = load_or_create_state(STATE)
    retry = cfg['retry_min_seconds']
    while True:
        try:
            state = register(cfg, state)
            poll_once(cfg, state)
            retry = cfg['retry_min_seconds']
        except NotifyError as exc:
            print(f'WARN: {exc}', file=sys.stderr)
            time.sleep(retry)
            retry = min(cfg['retry_max_seconds'], max(cfg['retry_min_seconds'], retry * 2))


def self_test() -> None:
    cfg = {
        'schema': 1, 'enabled': False, 'endpoint': '', 'channel': 'stable',
        'long_poll_seconds': 55, 'retry_min_seconds': 5, 'retry_max_seconds': 300,
        'minimum_wake_interval_seconds': 60,
    }
    assert load_config_for_test(cfg)['enabled'] is False
    state = initial_state()
    assert should_wake(state, {'schema': 1, 'action': 'check', 'nonce': 'a' * 16}, 60, 1000)
    state['last_notification_nonce'] = 'a' * 16
    assert not should_wake(state, {'schema': 1, 'action': 'check', 'nonce': 'a' * 16}, 60, 2000)
    state['last_notification_nonce'] = None
    state['last_wake_epoch'] = 980
    assert not should_wake(state, {'schema': 1, 'action': 'check', 'nonce': 'b' * 16}, 60, 1000)
    assert not should_wake(state, {'schema': 1, 'action': 'apply', 'nonce': 'c' * 16}, 60, 2000)
    assert same_https_origin('https://ota.example.test/v1/a', 'https://ota.example.test/v1/b')
    assert not same_https_origin('https://ota.example.test/v1/a', 'https://other.example.test/v1/b')
    assert not same_https_origin('https://ota.example.test/v1/a', 'http://ota.example.test/v1/b')
    try:
        validate_endpoint('http://ota.example.test')
    except NotifyError:
        pass
    else:
        raise AssertionError('HTTP endpoint must be rejected')
    print('PASS: OTA notifications only wake the signed updater, reject replay, cross-origin redirects and HTTP.')


def load_config_for_test(value: dict[str, Any]) -> dict[str, Any]:
    if set(value) != ALLOWED_CONFIG_KEYS or value.get('schema') != 1:
        raise NotifyError('test config schema invalid')
    if value['enabled']:
        validate_endpoint(value['endpoint'])
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=pathlib.Path, default=CONFIG)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('command', nargs='?', choices=('daemon', 'identity'), default='daemon')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    try:
        cfg = load_config(args.config)
        if args.command == 'identity':
            state = load_or_create_state(STATE)
            print(json.dumps({'device_id': state['device_id'], 'registered': bool(state.get('registration_token'))}, sort_keys=True))
            return 0
        return daemon(cfg)
    except (NotifyError, OSError, subprocess.SubprocessError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
