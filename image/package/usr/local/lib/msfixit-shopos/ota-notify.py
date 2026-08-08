#!/usr/bin/env python3
"""ShopOS OTA notification client; notifications only wake the signed local updater."""
from __future__ import annotations
import argparse,json,os,pathlib,platform,secrets,subprocess,sys,time,urllib.error,urllib.parse,urllib.request,uuid
from typing import Any
CONFIG=pathlib.Path('/etc/msfixit-shopos/ota-notify.json');STATE=pathlib.Path('/var/lib/msfixit-shopos/update/device-notify.json');VERSION_FILE=pathlib.Path('/usr/share/msfixit-shopos/build-info.txt');UPDATE_AGENT=pathlib.Path('/usr/local/sbin/msfixit-update-agent');MAX_RESPONSE=256*1024
ALLOWED_CONFIG_KEYS={'schema','enabled','endpoint','channel','long_poll_seconds','retry_min_seconds','retry_max_seconds','minimum_wake_interval_seconds'}
class NotifyError(RuntimeError):pass
def load_json(p):
 try:v=json.loads(p.read_text(encoding='utf-8'))
 except (OSError,json.JSONDecodeError) as e:raise NotifyError(f'cannot read valid JSON: {p}') from e
 if not isinstance(v,dict):raise NotifyError('JSON document must be an object')
 return v
def validate_endpoint(e):
 p=urllib.parse.urlparse(e)
 if p.scheme!='https' or not p.hostname or p.username or p.password or p.query or p.fragment:raise NotifyError('OTA notification endpoint must be a clean HTTPS origin')
def same_https_origin(a,b):
 x=urllib.parse.urlparse(a);y=urllib.parse.urlparse(b);return x.scheme==y.scheme=='https' and x.hostname==y.hostname and (x.port or 443)==(y.port or 443)
def load_config(p):
 c=load_json(p)
 if set(c)!=ALLOWED_CONFIG_KEYS or c.get('schema')!=1 or not isinstance(c.get('enabled'),bool) or c.get('channel') not in {'stable','candidate'}:raise NotifyError('invalid OTA notification configuration')
 if c['enabled']:validate_endpoint(c['endpoint'])
 for k in ('long_poll_seconds','retry_min_seconds','retry_max_seconds','minimum_wake_interval_seconds'):
  if not isinstance(c.get(k),int) or c[k]<1:raise NotifyError(f'invalid {k}')
 if not 10<=c['long_poll_seconds']<=120 or c['retry_min_seconds']>c['retry_max_seconds']:raise NotifyError('invalid timing configuration')
 return c
def atomic_write_json(p,v):
 p.parent.mkdir(mode=0o700,parents=True,exist_ok=True);t=p.with_suffix(p.suffix+'.new');flags=os.O_WRONLY|os.O_CREAT|os.O_EXCL
 if hasattr(os,'O_NOFOLLOW'):flags|=os.O_NOFOLLOW
 fd=os.open(t,flags,0o600)
 try:
  with os.fdopen(fd,'w',encoding='utf-8') as h:json.dump(v,h,sort_keys=True);h.write('\n');h.flush();os.fsync(h.fileno())
  os.replace(t,p);os.chmod(p,0o600)
 finally:
  try:t.unlink()
  except FileNotFoundError:pass
def read_version():
 try:
  for l in VERSION_FILE.read_text(encoding='utf-8').splitlines():
   if l.startswith('SHOPOS_VERSION='):return l.split('=',1)[1].strip() or 'unknown'
 except OSError:pass
 return 'unknown'
def initial_state():return {'schema':1,'device_id':str(uuid.uuid4()),'registration_token':None,'last_notification_nonce':None,'last_wake_epoch':0,'client_instance':secrets.token_hex(16)}
def load_or_create_state(p):
 if not p.exists():s=initial_state();atomic_write_json(p,s);return s
 s=load_json(p);expected={'schema','device_id','registration_token','last_notification_nonce','last_wake_epoch','client_instance'}
 if set(s)!=expected or s.get('schema')!=1:raise NotifyError('invalid OTA notification state')
 try:uuid.UUID(str(s['device_id']))
 except (ValueError,TypeError) as e:raise NotifyError('invalid device_id') from e
 if s['registration_token'] is not None and (not isinstance(s['registration_token'],str) or len(s['registration_token'])<32):raise NotifyError('invalid registration token')
 return s
def endpoint_url(b,s):validate_endpoint(b);return b.rstrip('/')+s
def request_json(url,*,method='GET',payload=None,token=None,timeout=30):
 body=None;headers={'Accept':'application/json','User-Agent':'ShopOS-OTA-Notify/1'}
 if payload is not None:body=json.dumps(payload,separators=(',',':')).encode();headers['Content-Type']='application/json'
 if token:headers['Authorization']=f'Bearer {token}'
 try:
  with urllib.request.urlopen(urllib.request.Request(url,data=body,headers=headers,method=method),timeout=timeout) as r:
   if not same_https_origin(url,r.geturl()):raise NotifyError('redirect outside configured HTTPS origin')
   raw=r.read(MAX_RESPONSE+1)
 except (urllib.error.URLError,TimeoutError,ValueError) as e:raise NotifyError('OTA notification request failed') from e
 if len(raw)>MAX_RESPONSE:raise NotifyError('response too large')
 try:v=json.loads(raw)
 except json.JSONDecodeError as e:raise NotifyError('invalid JSON response') from e
 if not isinstance(v,dict):raise NotifyError('response must be object')
 return v
def register(c,s):
 if s.get('registration_token'):return s
 payload={'schema':1,'device_id':s['device_id'],'client_instance':s['client_instance'],'architecture':platform.machine(),'shopos_version':read_version(),'channel':c['channel']};r=request_json(endpoint_url(c['endpoint'],'/v1/devices/register'),method='POST',payload=payload);t=r.get('token')
 if not isinstance(t,str) or len(t)<32:raise NotifyError('invalid device token')
 s['registration_token']=t;atomic_write_json(STATE,s);return s
def report(c,s,path,payload):
 t=s.get('registration_token')
 if not isinstance(t,str):return
 did=urllib.parse.quote(str(s['device_id']),safe='');request_json(endpoint_url(c['endpoint'],f'/v1/devices/{did}/{path}'),method='POST',payload=payload,token=t)
def should_wake(s,n,minimum,now):
 nonce=n.get('nonce');return n.get('schema')==1 and n.get('action')=='check' and isinstance(nonce,str) and 16<=len(nonce)<=256 and nonce!=s.get('last_notification_nonce') and now-int(s.get('last_wake_epoch') or 0)>=minimum
def wake_update_agent(s,nonce):
 r=subprocess.run([str(UPDATE_AGENT),'run'],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=3600,check=False);s['last_notification_nonce']=nonce;s['last_wake_epoch']=int(time.time());atomic_write_json(STATE,s);return r
def poll_once(c,s):
 t=s.get('registration_token')
 if not isinstance(t,str):raise NotifyError('device not registered')
 did=urllib.parse.quote(str(s['device_id']),safe='');n=request_json(endpoint_url(c['endpoint'],f"/v1/devices/{did}/notifications?wait={c['long_poll_seconds']}"),token=t,timeout=c['long_poll_seconds']+10)
 if not should_wake(s,n,c['minimum_wake_interval_seconds'],int(time.time())):return False
 r=wake_update_agent(s,str(n['nonce']));result='success' if r.returncode==0 else 'failed'
 try:report(c,s,'result',{'result':result})
 except NotifyError as e:print(f'WARN: update result report failed: {e}',file=sys.stderr)
 if r.returncode!=0:raise NotifyError(r.stderr.strip() or 'signed update agent failed')
 return True
def daemon(c):
 if not c['enabled']:print('OTA notification client disabled; signed GitHub polling fallback remains active.');return 0
 s=load_or_create_state(STATE);retry=c['retry_min_seconds']
 while True:
  try:
   s=register(c,s);report(c,s,'heartbeat',{'shopos_version':read_version()});poll_once(c,s);retry=c['retry_min_seconds']
  except NotifyError as e:print(f'WARN: {e}',file=sys.stderr);time.sleep(retry);retry=min(c['retry_max_seconds'],max(c['retry_min_seconds'],retry*2))
def self_test():
 s=initial_state();assert should_wake(s,{'schema':1,'action':'check','nonce':'a'*16},60,1000);s['last_notification_nonce']='a'*16;assert not should_wake(s,{'schema':1,'action':'check','nonce':'a'*16},60,2000);assert same_https_origin('https://ota.example/a','https://ota.example/b');assert not same_https_origin('https://ota.example/a','https://evil.example/b');print('PASS: OTA notification security self-test')
def main():
 p=argparse.ArgumentParser();p.add_argument('--config',type=pathlib.Path,default=CONFIG);p.add_argument('--self-test',action='store_true');p.add_argument('command',nargs='?',choices=('daemon','identity'),default='daemon');a=p.parse_args()
 if a.self_test:self_test();return 0
 try:
  c=load_config(a.config)
  if a.command=='identity':s=load_or_create_state(STATE);print(json.dumps({'device_id':s['device_id'],'registered':bool(s.get('registration_token'))}));return 0
  return daemon(c)
 except (NotifyError,OSError,subprocess.SubprocessError) as e:print(f'ERROR: {e}',file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
