#!/usr/bin/env python3
from __future__ import annotations
import pathlib,re,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
TARGETS=[ROOT/'tests',ROOT/'.github'/'workflows']
errors=[];warnings=[]
run_id=re.compile(r'actions/runs/\d{6,}')
artifact_id=re.compile(r'(?i)artifact(?:_|-| )?id\s*[:=]\s*["\']?\d{6,}')
pr_ref=re.compile(r'(?i)(?:refs/pull/|pull/|pr[-_ ]?)\d{1,5}')
fragile_sed=re.compile(r"sed\s+-n\s+['\"]/[^'\"]+/,/[^'\"]*(?:usr\\/|etc\\/|share\\/|assets\\/)[^'\"]+/p['\"]")
source_pin=re.compile(r'(?i)(?:EXPECTED_|PINNED_)?(?:COMMIT|SHA)\s*[:=]\s*["\']?[0-9a-f]{40}["\']?')
for base in TARGETS:
    if not base.exists(): continue
    for p in base.rglob('*'):
        if not p.is_file() or p.suffix not in {'.sh','.py','.yml','.yaml'}: continue
        text=p.read_text(encoding='utf-8',errors='replace')
        rel=p.relative_to(ROOT)
        if rel.as_posix()=='tests/test-ci-test-hygiene.py': continue
        for n,line in enumerate(text.splitlines(),1):
            stripped=line.strip()
            if stripped.startswith('#'): continue
            if run_id.search(line): errors.append(f'{rel}:{n}: hard-coded historical Actions run URL/ID')
            if artifact_id.search(line): errors.append(f'{rel}:{n}: hard-coded artifact id')
            if pr_ref.search(line) and ('github.event.pull_request' not in line): warnings.append(f'{rel}:{n}: possible hard-coded PR reference')
            if fragile_sed.search(line): errors.append(f'{rel}:{n}: fragile sed range anchored to a concrete repository path')
            if source_pin.search(line) and ('github.sha' not in line and 'event.pull_request.head.sha' not in line): warnings.append(f'{rel}:{n}: fixed commit SHA; verify this is intentional provenance, not stale test input')
# Workflow checkout should derive PR source dynamically, not from a historical PR/run constant.
for wf in (ROOT/'.github'/'workflows').glob('*.y*ml') if (ROOT/'.github'/'workflows').exists() else []:
    text=wf.read_text(encoding='utf-8',errors='replace')
    if 'pull_request:' in text and 'actions/checkout@' in text:
        has_dynamic=('github.event.pull_request.head.sha' in text or 'github.sha' in text or 'github.event.pull_request.merge_commit_sha' in text)
        if not has_dynamic:
            warnings.append(f'{wf.relative_to(ROOT)}: checkout source is not explicitly tied to a current GitHub event SHA')
for w in warnings: print('WARN:',w)
if errors:
    for e in errors: print('FAIL:',e,file=sys.stderr)
    print(f'FAIL: {len(errors)} stale-test anti-pattern(s) found; {len(warnings)} warning(s).',file=sys.stderr)
    raise SystemExit(1)
print(f'PASS: no blocking stale-test anti-patterns found; {len(warnings)} warning(s) for review.')
