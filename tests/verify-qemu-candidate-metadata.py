#!/usr/bin/env python3
"""Validate that a pinned GitHub Actions artifact belongs to the expected ShopOS build source."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def validate(meta: dict, expected_id: int, expected_digest: str, expected_source: str) -> list[str]:
    errors: list[str] = []
    if meta.get("id") != expected_id:
        errors.append(f"artifact id mismatch: {meta.get('id')} != {expected_id}")
    if meta.get("digest") != expected_digest:
        errors.append(f"artifact digest mismatch: {meta.get('digest')} != {expected_digest}")
    if meta.get("expired") is not False:
        errors.append("artifact is expired or expiry state is not false")
    workflow_run = meta.get("workflow_run") or {}
    if workflow_run.get("head_sha") != expected_source:
        errors.append(
            f"artifact source mismatch: {workflow_run.get('head_sha')} != {expected_source}"
        )
    return errors


def self_test() -> int:
    source = "a" * 40
    digest = "sha256:" + "b" * 64
    good = {
        "id": 42,
        "digest": digest,
        "expired": False,
        "workflow_run": {"head_sha": source},
    }
    assert validate(good, 42, digest, source) == []

    wrong_id = dict(good)
    wrong_id["id"] = 99
    assert any("artifact id mismatch" in e for e in validate(wrong_id, 42, digest, source))

    wrong_digest = dict(good)
    wrong_digest["digest"] = "sha256:" + "c" * 64
    assert any("artifact digest mismatch" in e for e in validate(wrong_digest, 42, digest, source))

    expired = dict(good)
    expired["expired"] = True
    assert any("expired" in e for e in validate(expired, 42, digest, source))

    wrong_source = {**good, "workflow_run": {"head_sha": "d" * 40}}
    assert any("source mismatch" in e for e in validate(wrong_source, 42, digest, source))
    print("verify-qemu-candidate-metadata self-test: PASS")
    return 0


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) != 4:
        print(
            "usage: verify-qemu-candidate-metadata.py <metadata.json> <artifact-id> <digest> <source-sha>",
            file=sys.stderr,
        )
        return 2
    path, artifact_id, digest, source = argv
    try:
        meta = json.loads(Path(path).read_text(encoding="utf-8"))
        expected_id = int(artifact_id)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"candidate metadata validation error: {exc}", file=sys.stderr)
        return 2
    errors = validate(meta, expected_id, digest, source)
    if errors:
        for error in errors:
            print(f"candidate metadata validation failed: {error}", file=sys.stderr)
        return 1
    print("candidate metadata validation: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
