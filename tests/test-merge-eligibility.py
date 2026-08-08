#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts/check-merge-eligibility.py"
REQUIRED = [
    "ShopOS integrated validation",
    "Workflow integrity gate",
    "Admin console foundation",
    "Build ShopOS image",
    "ShopOS release gate",
]


def evidence(**overrides):
    head = overrides.pop("head_sha", "abc123")
    value = {
        "head_sha": head,
        "tested_sha": head,
        "base": "integration/shopos-master-consolidation",
        "mode": "feature",
        "draft": False,
        "body": "Product change",
        "labels": [],
        "workflows": [
            {"name": name, "head_sha": head, "run_id": idx + 1, "status": "completed", "conclusion": "success"}
            for idx, name in enumerate(REQUIRED)
        ],
    }
    value.update(overrides)
    return value


def run_case(data, should_pass, expected=None):
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as handle:
        json.dump(data, handle)
        path = handle.name
    result = subprocess.run(["python3", str(CHECKER), path], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    pathlib.Path(path).unlink(missing_ok=True)
    assert (result.returncode == 0) is should_pass, result.stdout
    if expected:
        assert expected in result.stdout, result.stdout


def main():
    run_case(evidence(), True, "ELIGIBLE FOR MAIN")
    run_case(evidence(draft=True), False, "PR is still Draft")
    run_case(evidence(body="NO-MERGE-TO-MAIN\ntemporary harness"), False, "explicitly forbids")
    run_case(evidence(labels=["no-main-merge"]), False, "blocking label")
    run_case(evidence(labels=["requires-physical-validation"]), False, "physical-validation")
    run_case(evidence(tested_sha="oldsha"), False, "tested SHA does not match")
    missing = evidence()
    missing["workflows"] = missing["workflows"][:-1]
    run_case(missing, False, "required workflow missing")
    failed = evidence()
    failed["workflows"][0]["conclusion"] = "failure"
    run_case(failed, False, "not success")
    skipped = evidence()
    skipped["workflows"][1]["conclusion"] = "skipped"
    run_case(skipped, False, "skipped")
    pending = evidence()
    pending["workflows"][2]["status"] = "in_progress"
    pending["workflows"][2]["conclusion"] = ""
    run_case(pending, False, "not completed")
    promotion = evidence(base="main", mode="promotion")
    run_case(promotion, True)
    bad_promotion = evidence(base="integration/shopos-master-consolidation", mode="promotion")
    run_case(bad_promotion, False, "promotion PR must target main")
    print("PASS: production merge eligibility is fail-closed for draft, no-main, stale SHA and incomplete/failed/skipped gates.")


if __name__ == "__main__":
    main()
