#!/usr/bin/env python3
"""Minimal ShopOS OTA control plane: registration, long-poll wake, heartbeat/results."""
from __future__ import annotations
import argparse,hashlib,hmac,json,os,secrets,sqlite3,threading,time,urllib.parse
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
MAX_BODY=65536;LOCK=threading.Lock();WAIT=threading.Condition()
def token_hash(t):return hashlib.sha256(t.encode()).hexdigest()
def connect(p):
 d=sqlite3.connect(p,timeout=10);d.row_factory=sqlite3.Row;d.execute('PRAGMA journal_mode=WAL');return d
def init_db(p):
 with connect(p) as d:d.executescript("""CREATE TABLE IF NOT EXISTS devices(device_id TEXT PRIMARY KEY,token_hash TEXT NOT NULL,client_instance TEXT NOT NULL,architecture TEXT NOT NULL,shopos_version TEXT NOT NULL,channel TEXT NOT NULL CHECK(channel IN ('stable','candidate')),registered_at INTEGER NOT NULL,last_seen INTEGER NOT NULL,revoked INTEGER NOT NULL DEFAULT 0,last_update_result TEXT,last_notification_id INTEGER NOT NULL DEFAULT 0);CREATE TABLE IF NOT EXISTS notifications(id INTEGER PRIMARY KEY AUTOINCREMENT,device_id TEXT,channel TEXT,nonce TEXT NOT NULL UNIQUE,created_at INTEGER NOT NULL);""")
def validate_registration(x):
 if set(x)!={'schema','device_id','client_instance','architecture','shopos_version','channel'} or x.get('schema')!=1 or x.get('channel') not in ('stable','candidate'):raise ValueError()
 for k in ('device_id','client_instance','architecture','shopos_version'):
  if not isinstance(x[k],str) or not 1<=len(x[k])<=256:raise ValueError()
class H(BaseHTTPRequestHandler):
 def out(self,n,x):
  b=json.dumps(x,separators=(',',':')).encode();self.send_response(n);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
 def body(self):
  n=int(self.headers.get('Content-Length','0'))
  if n<2 or n>MAX_BODY:raise ValueError()
  x=json.loads(self.rfile.read(n))
  if not isinstance(x,dict):raise ValueError()
  return x
 def bearer(self):
  x=self.headers.get('Authorization','');return x[7:] if x.startswith('Bearer ') else ''
 def device(self,i):
  with connect(self.server.db) as d:r=d.execute('SELECT * FROM devices WHERE device_id=?',(i,)).fetchone()
  return r if r and not r['revoked'] and hmac.compare_digest(r['token_hash'],token_hash(self.bearer())) else None
 def do_POST(self):
  try:
   p=urllib.parse.urlparse(self.path).path
   if p=='/v1/devices/register':
    x=self.body();validate_registration(x);t=secrets.token_urlsafe(32);n=int(time.time())
    with LOCK,connect(self.server.db) as d:
     old=d.execute('SELECT client_instance,revoked FROM devices WHERE device_id=?',(x['device_id'],)).fetchone()
     if old and (old['revoked'] or old['client_instance']!=x['client_instance']):self.out(409,{'error':'identity_conflict'});return
     d.execute('INSERT INTO devices(device_id,token_hash,client_instance,architecture,shopos_version,channel,registered_at,last_seen) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(device_id) DO UPDATE SET token_hash=excluded.token_hash,architecture=excluded.architecture,shopos_version=excluded.shopos_version,channel=excluded.channel,last_seen=excluded.last_seen',(x['device_id'],token_hash(t),x['client_instance'],x['architecture'],x['shopos_version'],x['channel'],n,n))
    self.out(201,{'schema':1,'token':t});return
   q=p.strip('/').split('/')
   if len(q)==4 and q[:2]==['v1','devices'] and q[3] in ('heartbeat','result'):
    i=urllib.parse.unquote(q[2]);r=self.device(i)
    if not r:self.out(401,{'error':'unauthorized'});return
    x=self.body();n=int(time.time())
    with LOCK,connect(self.server.db) as d:
     if q[3]=='heartbeat':
      v=x.get('shopos_version',r['shopos_version'])
      if not isinstance(v,str) or not 1<=len(v)<=256:raise ValueError()
      d.execute('UPDATE devices SET last_seen=?,shopos_version=? WHERE device_id=?',(n,v,i))
     else:
      v=x.get('result')
      if v not in ('success','failed','staged','reboot_pending','rolled_back'):raise ValueError()
      d.execute('UPDATE devices SET last_seen=?,last_update_result=? WHERE device_id=?',(n,v,i))
    self.out(200,{'ok':True});return
   if p=='/v1/admin/notify':
    if not hmac.compare_digest(self.bearer(),self.server.admin):self.out(401,{'error':'unauthorized'});return
    x=self.body();c=x.get('channel');i=x.get('device_id')
    if c not in ('stable','candidate') or (i is not None and not isinstance(i,str)):raise ValueError()
    nonce=secrets.token_urlsafe(24)
    with LOCK,connect(self.server.db) as d:d.execute('INSERT INTO notifications(device_id,channel,nonce,created_at) VALUES(?,?,?,?)',(i,c,nonce,int(time.time())))
    with WAIT:WAIT.notify_all()
    self.out(202,{'ok':True,'nonce':nonce});return
   self.out(404,{'error':'not_found'})
  except (ValueError,json.JSONDecodeError):self.out(400,{'error':'bad_request'})
  except Exception:self.out(500,{'error':'internal_error'})
 def do_GET(self):
  try:
   p=urllib.parse.urlparse(self.path);q=p.path.strip('/').split('/')
   if len(q)==4 and q[:2]==['v1','devices'] and q[3]=='notifications':
    i=urllib.parse.unquote(q[2]);r=self.device(i)
    if not r:self.out(401,{'error':'unauthorized'});return
    wait=min(120,max(1,int(urllib.parse.parse_qs(p.query).get('wait',['30'])[0])));end=time.monotonic()+wait
    while True:
     with LOCK,connect(self.server.db) as d:
      cur=d.execute('SELECT channel,last_notification_id FROM devices WHERE device_id=?',(i,)).fetchone();note=d.execute('SELECT id,nonce FROM notifications WHERE id>? AND (device_id=? OR (device_id IS NULL AND channel=?)) ORDER BY id LIMIT 1',(cur['last_notification_id'],i,cur['channel'])).fetchone()
      if note:d.execute('UPDATE devices SET last_notification_id=?,last_seen=? WHERE device_id=?',(note['id'],int(time.time()),i))
     if note:self.out(200,{'schema':1,'action':'check','nonce':note['nonce']});return
     left=end-time.monotonic()
     if left<=0:self.out(200,{'schema':1,'action':'none'});return
     with WAIT:WAIT.wait(min(left,5))
   self.out(404,{'error':'not_found'})
  except (ValueError,OverflowError):self.out(400,{'error':'bad_request'})
  except Exception:self.out(500,{'error':'internal_error'})
def main():
 a=argparse.ArgumentParser();a.add_argument('--listen',default='127.0.0.1');a.add_argument('--port',type=int,default=8088);a.add_argument('--db',default='ota-control.sqlite3');x=a.parse_args();admin=os.environ.get('SHOPOS_OTA_ADMIN_TOKEN','')
 if len(admin)<32:raise SystemExit('SHOPOS_OTA_ADMIN_TOKEN must be at least 32 characters')
 Path(x.db).parent.mkdir(parents=True,exist_ok=True);init_db(x.db);s=ThreadingHTTPServer((x.listen,x.port),H);s.db=x.db;s.admin=admin;s.serve_forever()
if __name__=='__main__':main()
