#!/usr/bin/env python3
from __future__ import annotations
import argparse, base64, hashlib, json, os, shutil, subprocess, sys, tarfile, tempfile, time
from pathlib import Path

ALLOWED_PACKAGE_FIELDS={"schema","app_id","version","manifest_sha256","payload_sha256","signature"}

def fail(message:str)->None: raise ValueError(message)

def canonical(data:dict)->bytes:
    return json.dumps({k:v for k,v in data.items() if k!="signature"},sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()

def verify_signature(meta:dict,key:Path)->None:
    try: sig=base64.b64decode(meta["signature"],validate=True)
    except Exception as exc: raise ValueError("invalid signature encoding") from exc
    with tempfile.TemporaryDirectory() as td:
        p=Path(td); (p/"payload").write_bytes(canonical(meta)); (p/"sig").write_bytes(sig)
        result=subprocess.run(["openssl","pkeyutl","-verify","-pubin","-inkey",str(key),"-rawin","-in",str(p/"payload"),"-sigfile",str(p/"sig")],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if result.returncode: fail("signature verification failed")

def digest(path:Path)->str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""): h.update(chunk)
    return h.hexdigest()

def safe_extract(archive:tarfile.TarFile,target:Path)->None:
    for member in archive.getmembers():
        if member.islnk() or member.issym(): fail("links are forbidden")
        dest=(target/member.name).resolve()
        if target.resolve() not in dest.parents and dest!=target.resolve(): fail("path traversal detected")
    archive.extractall(target)

def main()->int:
    p=argparse.ArgumentParser(); p.add_argument("package",type=Path); p.add_argument("--public-key",required=True,type=Path); p.add_argument("--root",type=Path,default=Path("/var/lib/msfixit-shopos/apps")); p.add_argument("--audit",type=Path,default=Path("/var/log/msfixit-shopos/app-install.jsonl")); p.add_argument("--fail-after-stage",action="store_true"); a=p.parse_args()
    try:
        with tempfile.TemporaryDirectory(prefix="shopos-app-") as td:
            stage=Path(td); safe_extract(tarfile.open(a.package,"r:*"),stage)
            meta=json.loads((stage/"package.json").read_text())
            if set(meta)!=ALLOWED_PACKAGE_FIELDS or meta.get("schema")!=1: fail("invalid package metadata")
            app_id=str(meta["app_id"]); version=str(meta["version"])
            if not app_id.startswith("at.msfixit.shopos.") or "/" in app_id or ".." in app_id: fail("invalid app id")
            manifest=stage/"manifest.json"; payload=stage/"payload.tar"
            if digest(manifest)!=meta["manifest_sha256"] or digest(payload)!=meta["payload_sha256"]: fail("package digest mismatch")
            verify_signature(meta,a.public_key)
            app_stage=stage/"app"; app_stage.mkdir(); safe_extract(tarfile.open(payload,"r:"),app_stage)
            subprocess.run([sys.executable,str(Path(__file__).with_name("validate-shopos-app.py")),str(manifest)],check=True)
            if a.fail_after_stage: fail("simulated failure")
            a.root.mkdir(parents=True,exist_ok=True); target=a.root/app_id; backup=a.root/(app_id+".rollback")
            if backup.exists(): shutil.rmtree(backup)
            if target.exists(): os.replace(target,backup)
            try: os.replace(app_stage,target)
            except Exception:
                if backup.exists(): os.replace(backup,target)
                raise
            if backup.exists(): shutil.rmtree(backup)
            a.audit.parent.mkdir(parents=True,exist_ok=True)
            with a.audit.open("a",encoding="utf-8") as log: log.write(json.dumps({"time":int(time.time()),"action":"install","app_id":app_id,"version":version,"result":"success"},sort_keys=True)+"\n")
            print(f"INSTALLED: {app_id} {version}")
            return 0
    except (OSError,ValueError,KeyError,json.JSONDecodeError,tarfile.TarError,subprocess.CalledProcessError) as exc:
        print(f"FAILED: {exc}",file=sys.stderr); return 1

if __name__=="__main__": raise SystemExit(main())
