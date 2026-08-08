#!/usr/bin/env python3
"""Fail-closed evaluator for ShopOS production merge eligibility.

This program is intentionally side-effect free. It decides whether a PR head is
eligible to progress toward main, but it never merges, labels or edits a PR.
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any

REQUIRED_WORKFLOWS = {
    "ShopOS integrated validation",
    "Workflow integrity gate",
    "Admin console foundation",
    "Build ShopOS image",
    "ShopOS release gate",
}
BLOCKING_MARKERS = {"NO-MERGE-TO-MAIN", "NO_MAIN_MERGE"}
BLOCKING_LABELS = {"no-main-merge", "requires-physical-validation"}
SUCCESS = "success"
TERMINAL_BLOCKING = {"failure", "cancelled", "timed_out", "action_required", "stale", "neutral", "skipped"}


def load(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("eligibility input must be a JSON object")
    return value


def evaluate(data: dict[str, Any]) -> list[str]:
    blockers: list[str] = []
    head_sha = str(data.get("head_sha") or "")
    tested_sha = str(data.get("tested_sha") or "")
    body = str(data.get("body") or "")
    labels = {str(v) for v in data.get("labels", []) if isinstance(v, str)}
    workflows = data.get("workflows")

    if data.get("draft") is True:
        blockers.append("PR is still Draft")
    if not head_sha:
        blockers.append("PR head SHA is missing")
    if tested_sha != head_sha:
        blockers.append("tested SHA does not match current PR head")
    if any(marker in body for marker in BLOCKING_MARKERS):
        blockers.append("PR description explicitly forbids merge to main")
    label_blockers = sorted(labels & BLOCKING_LABELS)
    if label_blockers:
        blockers.append("blocking label present: " + ", ".join(label_blockers))

    # Until the consolidation is complete, feature PRs may target the integration
    # branch. The final promotion PR to main must itself target main. This keeps
    # one canonical reviewed promotion point instead of silently bypassing it.
    base = str(data.get("base") or "")
    mode = str(data.get("mode") or "feature")
    if mode == "promotion":
        if base != "main":
            blockers.append("production promotion PR must target main")
    elif base not in {"integration/shopos-master-consolidation", "main"}:
        blockers.append(f"unsupported protected base branch: {base or '<missing>'}")

    if not isinstance(workflows, list):
        blockers.append("workflow evidence is missing")
        return blockers

    by_name: dict[str, list[dict[str, Any]]] = {}
    for run in workflows:
        if not isinstance(run, dict):
            continue
        name = str(run.get("name") or "")
        if name:
            by_name.setdefault(name, []).append(run)

    for required in sorted(REQUIRED_WORKFLOWS):
        candidates = [r for r in by_name.get(required, []) if str(r.get("head_sha") or "") == head_sha]
        if not candidates:
            blockers.append(f"required workflow missing for current SHA: {required}")
            continue
        # Input should be newest-first; still prefer highest numeric run_id if present.
        newest = max(candidates, key=lambda r: int(r.get("run_id") or 0))
        status = str(newest.get("status") or "")
        conclusion = str(newest.get("conclusion") or "")
        if status != "completed":
            blockers.append(f"required workflow not completed: {required} ({status or 'unknown'})")
        elif conclusion != SUCCESS:
            reason = conclusion or "missing conclusion"
            blockers.append(f"required workflow is not success: {required} ({reason})")
        if conclusion in TERMINAL_BLOCKING:
            # Explicit branch kept for readability in machine-produced logs.
            pass

    return blockers


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="JSON evidence file")
    args = parser.parse_args()
    try:
        data = load(args.input)
        blockers = evaluate(data)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"BLOCKED: invalid eligibility evidence: {exc}", file=sys.stderr)
        return 2

    if blockers:
        print("NOT ELIGIBLE FOR MAIN")
        for blocker in blockers:
            print(f"- {blocker}")
        return 1

    print("ELIGIBLE FOR MAIN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
