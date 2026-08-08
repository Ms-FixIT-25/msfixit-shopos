#!/usr/bin/env python3
from __future__ import annotations
import argparse,pathlib,re,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
TARGETS=[ROOT/'tests',ROOT/'.github'/'workflows']
run_id=re.compile(r'actions/runs/\d{6,}')
artifact_id=re.compile(r'(?i)artifact(?:_|-| )?id\s*[:=]\s*["\']?\d{6,}')
pr_ref=re.compile(r'(?i)(?:refs/pull/\d+|github\.com/[^/]+/[^/]+/pull/\d+)')
fragile_sed=re.compile(r"sed\s+-n\s+['\"]/[^'\"]+/,/[^'\"]*(?:usr\\/|etc\\/|share\\/|assets\\/)[^'\"]+/p['\"]")
source_pin=re.compile(r'(?i)(?:EXPECTED_|PINNED_)?(?:COMMIT|SHA)\s*[:=]\s*["\']?[0-9a-f]{40}["\']?')

def changed_files(base_ref:str)->set[str]:
    if not base_ref:return set()
    subprocess.run(['git','fetch','--no-tags','origin',base_ref],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
    out=subprocess.check_output(['git','diff','--name-only',f'origin/{base_ref}...HEAD'],cwd=ROOT,text=True)
    return {line.strip() for line in out.splitlines() if line.strip()}

def audit(strict:set[str]|None):
    blocking=[];legacy=[];warnings=[]
    for base in TARGETS:
        if not base.exists():continue
        for p in base.rglob('*'):
            if not p.is_file() or p.suffix not in {'.sh','.py','.yml','.yaml'}:continue
            rel=p.relative_to(ROOT).as_posix()
            if rel=='tests/test-ci-test-hygiene.py':continue
            text=p.read_text(encoding='utf-8',errors='replace')
            for n,line in enumerate(text.splitlines(),1):
                if line.strip().startswith('#'):continue
                findings=[]
                if run_id.search(line):findings.append('hard-coded historical Actions run URL/ID')
                if artifact_id.search(line):findings.append('hard-coded artifact id')
                if fragile_sed.search(line):findings.append('fragile sed range anchored to a concrete repository path')
                for f in findings:
                    msg=f'{rel}:{n}: {f}'
                    (blocking if strict is None or rel in strict else legacy).append(msg)
                if pr_ref.search(line):warnings.append(f'{rel}:{n}: explicit PR reference; verify it is historical/documentary, not current validation input')
                if source_pin.search(line) and 'github.sha' not in line and 'event.pull_request.head.sha' not in line:warnings.append(f'{rel}:{n}: fixed commit SHA; verify intentional immutable provenance')
    return blocking,legacy,warnings

def main():
    p=argparse.ArgumentParser();p.add_argument('--base-ref',default='');a=p.parse_args()
    strict=changed_files(a.base_ref) if a.base_ref else None
    blocking,legacy,warnings=audit(strict)
    for x in legacy:print('LEGACY:',x)
    for x in warnings:print('WARN:',x)
    if blocking:
        for x in blocking:print('FAIL:',x,file=sys.stderr)
        print(f'FAIL: {len(blocking)} newly introduced/changed stale-test anti-pattern(s); {len(legacy)} pre-existing issue(s) reported without blocking.',file=sys.stderr)
        return 1
    print(f'PASS: no newly introduced stale-test anti-patterns; {len(legacy)} pre-existing issue(s), {len(warnings)} warning(s) reported without blocking.')
    return 0
if __name__=='__main__':raise SystemExit(main())
