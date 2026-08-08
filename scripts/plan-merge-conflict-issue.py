#!/usr/bin/env python3
"""Plan deduplicated ShopOS merge-conflict issue actions.

The planner is side-effect free. GitHub Actions supplies current PR mergeability and
any existing conflict issue, then executes the returned create/update/close plan.
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any

MARKER_PREFIX = "<!-- shopos-merge-conflict-pr:"


def marker(pr_number: int) -> str:
    return f"{MARKER_PREFIX}{pr_number} -->"


def conflict_detected(pr: dict[str, Any]) -> bool:
    mergeable = pr.get("mergeable")
    state = str(pr.get("mergeable_state") or "").lower()
    return mergeable is False or state == "dirty"


def mergeability_unknown(pr: dict[str, Any]) -> bool:
    mergeable = pr.get("mergeable")
    state = str(pr.get("mergeable_state") or "").lower()
    return mergeable is None or state in {"", "unknown"}


def issue_body(pr: dict[str, Any]) -> str:
    number = int(pr["number"])
    title = str(pr.get("title") or "")
    url = str(pr.get("html_url") or "")
    head_ref = str(pr.get("head_ref") or "")
    head_sha = str(pr.get("head_sha") or "")
    base_ref = str(pr.get("base_ref") or "")
    base_sha = str(pr.get("base_sha") or "")
    detected_at = str(pr.get("detected_at") or "")
    return "\n".join([
        marker(number),
        "## Blocking merge conflict",
        "",
        f"GitHub reports that PR #{number} cannot be merged cleanly.",
        "",
        f"- PR: [{title}]({url})",
        f"- Head: `{head_ref}` @ `{head_sha}`",
        f"- Base: `{base_ref}` @ `{base_sha}`",
        f"- Detected: `{detected_at}`",
        "",
        "This issue is managed automatically. The PR remains ineligible for production merge while this issue is open.",
        "No automatic force-merge or speculative conflict resolution is allowed.",
    ]) + "\n"


def plan(pr: dict[str, Any], existing: dict[str, Any] | None) -> dict[str, Any]:
    number = int(pr["number"])
    title = f"Merge conflict blocks PR #{number}: {str(pr.get('title') or '').strip()}"

    if mergeability_unknown(pr):
        return {
            "action": "block-unknown",
            "blocked": True,
            "reason": "GitHub mergeability is unknown; fail closed and retry later",
        }

    if conflict_detected(pr):
        body = issue_body(pr)
        if existing is None:
            return {"action": "create", "blocked": True, "title": title, "body": body}
        if str(existing.get("state") or "open") == "closed":
            return {
                "action": "reopen-update",
                "blocked": True,
                "issue_number": int(existing["number"]),
                "title": title,
                "body": body,
            }
        old_body = str(existing.get("body") or "")
        old_title = str(existing.get("title") or "")
        if old_body != body or old_title != title:
            return {
                "action": "update",
                "blocked": True,
                "issue_number": int(existing["number"]),
                "title": title,
                "body": body,
            }
        return {"action": "none", "blocked": True, "issue_number": int(existing["number"])}

    if existing is not None and str(existing.get("state") or "open") == "open":
        return {
            "action": "close",
            "blocked": False,
            "issue_number": int(existing["number"]),
            "reason": "GitHub reports the PR mergeable again",
        }
    return {"action": "none", "blocked": False}


def self_test() -> None:
    base = {
        "number": 123,
        "title": "Example product PR",
        "html_url": "https://github.com/Ms-FixIT-25/msfixit-shopos/pull/123",
        "head_ref": "feat/example",
        "head_sha": "a" * 40,
        "base_ref": "integration/shopos-master-consolidation",
        "base_sha": "b" * 40,
        "detected_at": "2026-08-08T09:44:00Z",
    }

    p = dict(base, mergeable=True, mergeable_state="clean")
    assert plan(p, None) == {"action": "none", "blocked": False}

    p = dict(base, mergeable=False, mergeable_state="dirty")
    created = plan(p, None)
    assert created["action"] == "create" and created["blocked"] is True
    assert marker(123) in created["body"]

    existing = {"number": 88, "state": "open", "title": created["title"], "body": created["body"]}
    repeated = plan(p, existing)
    assert repeated == {"action": "none", "blocked": True, "issue_number": 88}

    changed = dict(p, head_sha="c" * 40, detected_at="2026-08-08T10:00:00Z")
    updated = plan(changed, existing)
    assert updated["action"] == "update" and updated["issue_number"] == 88
    assert "c" * 40 in updated["body"]

    resolved = dict(base, mergeable=True, mergeable_state="clean")
    closed = plan(resolved, existing)
    assert closed["action"] == "close" and closed["blocked"] is False

    closed_issue = dict(existing, state="closed")
    reopened = plan(p, closed_issue)
    assert reopened["action"] == "reopen-update" and reopened["blocked"] is True

    unknown = dict(base, mergeable=None, mergeable_state="unknown")
    unknown_plan = plan(unknown, None)
    assert unknown_plan["action"] == "block-unknown" and unknown_plan["blocked"] is True

    print("PASS: merge-conflict issue planning is deduplicated, fail-closed and self-healing.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--pr-json")
    parser.add_argument("--existing-json")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.pr_json:
        parser.error("--pr-json is required unless --self-test is used")
    try:
        pr = json.loads(args.pr_json)
        existing = json.loads(args.existing_json) if args.existing_json else None
        if not isinstance(pr, dict) or (existing is not None and not isinstance(existing, dict)):
            raise ValueError("inputs must be JSON objects")
        print(json.dumps(plan(pr, existing), sort_keys=True))
        return 0
    except (ValueError, TypeError, json.JSONDecodeError, KeyError) as exc:
        print(json.dumps({"action": "block-unknown", "blocked": True, "reason": f"invalid mergeability evidence: {exc}"}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
