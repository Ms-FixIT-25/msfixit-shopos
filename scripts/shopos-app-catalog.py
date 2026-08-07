#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, sys
from pathlib import Path

RANK={"community":0,"professional":1,"enterprise":2,"developer":3}

def main()->int:
    p=argparse.ArgumentParser()
    p.add_argument("catalog",type=Path)
    p.add_argument("--license-json",type=Path)
    args=p.parse_args()
    try:
        catalog=json.loads(args.catalog.read_text(encoding="utf-8"))
        if catalog.get("schema")!=1 or not isinstance(catalog.get("apps"),list):
            raise ValueError("invalid catalog")
        license_data={"valid":False,"edition":"community","entitlements":[]}
        if args.license_json:
            license_data=json.loads(args.license_json.read_text(encoding="utf-8"))
        edition=license_data.get("edition","community") if license_data.get("valid") else "community"
        ent=set(license_data.get("entitlements",[]))
        result=[]
        for app in catalog["apps"]:
            required=app["edition"]
            granted=RANK.get(edition,-1)>=RANK[required] and app["entitlement"] in ent
            result.append({**app,"locked":not granted,"action":"install" if granted else "unlock"})
        print(json.dumps({"edition":edition,"apps":result},ensure_ascii=False,sort_keys=True))
        return 0
    except (OSError,ValueError,KeyError,json.JSONDecodeError) as exc:
        print(f"INVALID: {exc}",file=sys.stderr)
        return 1

if __name__=="__main__":
    raise SystemExit(main())
