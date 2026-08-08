#!/usr/bin/env python3
"""Minimal ShopOS OTA control plane.

Standard-library reference service for device registration, authenticated long-poll
wake notifications, heartbeats and update-result reporting. It never distributes
trusted executable update content; devices always wake the signed local updater.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

MAX_BODY = 64 * 1024
DB_LOCK = threading.Lock()
WAIT = threading.Condition()


def now() -> int:
    return int(time.time())


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def connect(path: str) -> sqlite3.Connection:
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('PRAGMA foreign_keys=ON')
    return db


def init_db(path: str) -> None:
    with connect(path) as db:
        db.executescript('''
        CREATE TABLE IF NOT EXISTS devices (
          device_id TEXT PRIMARY KEY,
          token_hash TEXT NOT NULL,
          client_instance TEXT NOT NULL,
          architecture TEXT NOT NULL,
          shopos_version TEXT NOT NULL,
          channel TEXT NOT NULL CHECK(channel IN ('stable','candidate')),
          registered_at INTEGER NOT NULL,
          last_seen INTEGER NOT NULL,
          revoked INTEGER NOT NULL DEFAULT 0,
          last_update_result TEXT
        );
        CREATE TABLE IF NOT EXISTS notifications (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          device_id TEXT,
          channel TEXT,
          nonce TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS notifications_device_idx ON notifications(device_id,id);
        CREATE INDEX IF NOT EXISTS notifications_channel_idx ON notifications(channel,id);
        ''')


def validate_registration(data: dict[str, Any]) -> None:
    required = {'schema','device_id','client_instance','architecture','shopos_version','channel'}
    if set(data) != required or data.get('schema') != 1:
        raise ValueError('invalid registration schema')
    if data['channel'] not in ('stable', 'candidate'):
        raise ValueError('invalid channel')
    for key in ('device_id','client_instance','architecture','shopos_version'):
        if not isinstance(data[key], str) or not 1 <= len(data[key]) <= 256:
            raise ValueError(f'invalid {key}')


class Handler(BaseHTTPRequestHandler):
    server_version = 'ShopOS-OTA-Control/1'

    def log_message(self, fmt: str, *args: Any) -> None:
        # Never log Authorization headers or request bodies.
        super().log_message(fmt, *args)

    @property
    def db_path(self) -> str:
        return self.server.db_path  # type: ignore[attr-defined]

    @property
    def admin_token(self) -> str:
        return self.server.admin_token  # type: ignore[attr-defined]

    def json_response(self, status: int, value: dict[str, Any]) -> None:
        raw = json.dumps(value, separators=(',', ':'), sort_keys=True).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(raw)

    def read_json(self) -> dict[str, Any]:
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError as exc:
            raise ValueError('invalid content length') from exc
        if length < 2 or length > MAX_BODY:
            raise ValueError('invalid body size')
        raw = self.rfile.read(length)
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError('body must be object')
        return value

    def bearer(self) -> str | None:
        value = self.headers.get('Authorization', '')
        return value[7:] if value.startswith('Bearer ') and len(value) > 7 else None

    def authenticate_device(self, device_id: str) -> sqlite3.Row | None:
        token = self.bearer()
        if not token:
            return None
        with connect(self.db_path) as db:
            row = db.execute('SELECT * FROM devices WHERE device_id=?', (device_id,)).fetchone()
        if not row or row['revoked'] or not hmac.compare_digest(row['token_hash'], token_hash(token)):
            return None
        return row

    def authenticate_admin(self) -> bool:
        token = self.bearer()
        return bool(token and self.admin_token and hmac.compare_digest(token, self.admin_token))

    def do_POST(self) -> None:
        try:
            self.route_post()
        except (ValueError, json.JSONDecodeError):
            self.json_response(400, {'error':'bad_request'})
        except Exception:
            self.json_response(500, {'error':'internal_error'})

    def route_post(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path == '/v1/devices/register':
            data = self.read_json(); validate_registration(data)
            token = secrets.token_urlsafe(32); stamp = now()
            with DB_LOCK, connect(self.db_path) as db:
                old = db.execute('SELECT client_instance,revoked FROM devices WHERE device_id=?',(data['device_id'],)).fetchone()
                if old and (old['revoked'] or old['client_instance'] != data['client_instance']):
                    self.json_response(409, {'error':'device_identity_conflict'}); return
                db.execute('''INSERT INTO devices(device_id,token_hash,client_instance,architecture,shopos_version,channel,registered_at,last_seen)
                    VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(device_id) DO UPDATE SET token_hash=excluded.token_hash,
                    architecture=excluded.architecture,shopos_version=excluded.shopos_version,channel=excluded.channel,last_seen=excluded.last_seen''',
                    (data['device_id'],token_hash(token),data['client_instance'],data['architecture'],data['shopos_version'],data['channel'],stamp,stamp))
            self.json_response(201, {'schema':1,'token':token}); return

        parts = path.strip('/').split('/')
        if len(parts) == 4 and parts[:2] == ['v1','devices'] and parts[3] in ('heartbeat','result'):
            device_id = urllib.parse.unquote(parts[2]); row = self.authenticate_device(device_id)
            if not row: self.json_response(401, {'error':'unauthorized'}); return
            data = self.read_json(); stamp = now()
            with DB_LOCK, connect(self.db_path) as db:
                if parts[3] == 'heartbeat':
                    version = data.get('shopos_version', row['shopos_version'])
                    if not isinstance(version,str) or len(version)>256: raise ValueError('version')
                    db.execute('UPDATE devices SET last_seen=?,shopos_version=? WHERE device_id=?',(stamp,version,device_id))
                else:
                    result = data.get('result')
                    if result not in ('success','failed','staged','reboot_pending','rolled_back'): raise ValueError('result')
                    db.execute('UPDATE devices SET last_seen=?,last_update_result=? WHERE device_id=?',(stamp,result,device_id))
            self.json_response(200, {'ok':True}); return

        if path == '/v1/admin/notify':
            if not self.authenticate_admin(): self.json_response(401, {'error':'unauthorized'}); return
            data = self.read_json(); channel=data.get('channel'); device_id=data.get('device_id')
            if channel not in ('stable','candidate') or (device_id is not None and not isinstance(device_id,str)):
                raise ValueError('notify')
            nonce=secrets.token_urlsafe(24)
            with DB_LOCK, connect(self.db_path) as db:
                db.execute('INSERT INTO notifications(device_id,channel,nonce,created_at) VALUES(?,?,?,?)',(device_id,channel,nonce,now()))
            with WAIT: WAIT.notify_all()
            self.json_response(202, {'ok':True,'nonce':nonce}); return
        self.json_response(404, {'error':'not_found'})

    def do_GET(self) -> None:
        try:
            parsed=urllib.parse.urlparse(self.path); parts=parsed.path.strip('/').split('/')
            if len(parts)==4 and parts[:2]==['v1','devices'] and parts[3]=='notifications':
                device_id=urllib.parse.unquote(parts[2]); row=self.authenticate_device(device_id)
                if not row: self.json_response(401, {'error':'unauthorized'}); return
                query=urllib.parse.parse_qs(parsed.query); wait=min(120,max(1,int(query.get('wait',['30'])[0])))
                deadline=time.monotonic()+wait
                while True:
                    with connect(self.db_path) as db:
                        note=db.execute('''SELECT nonce FROM notifications WHERE (device_id=? OR (device_id IS NULL AND channel=?)) ORDER BY id DESC LIMIT 1''',(device_id,row['channel'])).fetchone()
                    if note: self.json_response(200, {'schema':1,'action':'check','nonce':note['nonce']}); return
                    remaining=deadline-time.monotonic()
                    if remaining<=0: self.json_response(200, {'schema':1,'action':'none'}); return
                    with WAIT: WAIT.wait(timeout=min(remaining,5))
            self.json_response(404, {'error':'not_found'})
        except (ValueError, OverflowError): self.json_response(400, {'error':'bad_request'})
        except Exception: self.json_response(500, {'error':'internal_error'})


def main() -> int:
    p=argparse.ArgumentParser(); p.add_argument('--listen',default='127.0.0.1'); p.add_argument('--port',type=int,default=8088); p.add_argument('--db',default='ota-control.sqlite3')
    args=p.parse_args(); admin=os.environ.get('SHOPOS_OTA_ADMIN_TOKEN','')
    if len(admin)<32: raise SystemExit('SHOPOS_OTA_ADMIN_TOKEN must be at least 32 characters')
    Path(args.db).parent.mkdir(parents=True,exist_ok=True); init_db(args.db)
    server=ThreadingHTTPServer((args.listen,args.port),Handler); server.db_path=args.db; server.admin_token=admin
    server.serve_forever(); return 0

if __name__=='__main__': raise SystemExit(main())
