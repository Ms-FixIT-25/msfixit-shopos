#!/usr/bin/env python3
"""Create a reproducible ShopOS hardware validation report."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import platform
import subprocess
import sys
from typing import Any

ALLOWED_TESTS = {
    "boot-slot-a",
    "boot-slot-b",
    "rollback-unconfirmed",
    "power-loss-first-boot",
    "power-loss-update",
    "power-loss-database",
    "power-loss-backup",
    "disk-full",
    "network-loss",
    "dns-loss",
    "clock-skew",
    "soak-72h",
}


def command(*args: str) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_results(path: pathlib.Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list) or not data:
        raise ValueError("results must be a non-empty JSON array")
    seen: set[str] = set()
    for entry in data:
        if not isinstance(entry, dict) or set(entry) != {"test", "result", "notes"}:
            raise ValueError("each result must contain exactly test, result and notes")
        test = entry["test"]
        if test not in ALLOWED_TESTS or test in seen:
            raise ValueError(f"invalid or duplicate test: {test}")
        if entry["result"] not in {"pass", "fail", "blocked"}:
            raise ValueError(f"invalid result for {test}")
        if not isinstance(entry["notes"], str) or len(entry["notes"]) > 2000:
            raise ValueError(f"invalid notes for {test}")
        seen.add(test)
    return data


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=pathlib.Path, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--device-id", required=True)
    parser.add_argument("--results", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    if not args.image.is_file() or args.image.is_symlink():
        parser.error("image must be a regular non-symlink file")
    if len(args.commit) != 40 or any(c not in "0123456789abcdef" for c in args.commit):
        parser.error("commit must be a lowercase 40-character SHA")
    if not args.device_id.replace("-", "").replace("_", "").isalnum():
        parser.error("device-id must contain only letters, numbers, dash or underscore")

    results = load_results(args.results)
    report = {
        "schema": 1,
        "created_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "image": {
            "name": args.image.name,
            "sha256": sha256(args.image),
            "size": args.image.stat().st_size,
            "commit": args.commit,
        },
        "device": {
            "id": args.device_id,
            "model": command("tr", "-d", "\\0", "/proc/device-tree/model") if pathlib.Path("/proc/device-tree/model").exists() else platform.machine(),
            "serial": command("cat", "/sys/firmware/devicetree/base/serial-number"),
            "kernel": platform.release(),
            "os": command("sh", "-c", ". /etc/os-release 2>/dev/null; printf '%s' \"${PRETTY_NAME:-unknown}\""),
            "root_source": command("findmnt", "-n", "-o", "SOURCE", "/"),
            "root_label": command("findmnt", "-n", "-o", "PARTLABEL", "/"),
            "boot_cmdline": pathlib.Path("/proc/cmdline").read_text(encoding="utf-8").strip() if pathlib.Path("/proc/cmdline").exists() else "unknown",
        },
        "results": results,
        "summary": {
            "pass": sum(x["result"] == "pass" for x in results),
            "fail": sum(x["result"] == "fail" for x in results),
            "blocked": sum(x["result"] == "blocked" for x in results),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, args.output)
    print(json.dumps(report["summary"], sort_keys=True))
    return 1 if report["summary"]["fail"] else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
