#!/usr/bin/env python3
"""Strict, dependency-free validation for ShopOS application manifests v1."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REQUIRED = {"schema", "id", "name", "version", "core_api", "edition", "entitlements", "capabilities", "entrypoints"}
EDITIONS = {"community", "professional", "enterprise"}
CAPABILITIES = {"navigation", "background-job", "notifications", "catalog-read", "catalog-write", "orders-read", "orders-write", "documents", "printing", "external-network"}
ID_RE = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)+$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
TOKEN_RE = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
ADMIN_RE = re.compile(r"^/apps/[a-z0-9][a-z0-9/_-]*/$")


def fail(message: str) -> None:
    raise ValueError(message)


def validate(data: object) -> None:
    if not isinstance(data, dict):
        fail("manifest must be a JSON object")
    keys = set(data)
    missing = REQUIRED - keys
    unknown = keys - REQUIRED
    if missing:
        fail(f"missing fields: {', '.join(sorted(missing))}")
    if unknown:
        fail(f"unknown fields: {', '.join(sorted(unknown))}")
    if data["schema"] != 1:
        fail("schema must be 1")
    if not isinstance(data["id"], str) or len(data["id"]) > 128 or not ID_RE.fullmatch(data["id"]):
        fail("invalid application id")
    if not isinstance(data["name"], str) or not 1 <= len(data["name"]) <= 80:
        fail("invalid application name")
    if not isinstance(data["version"], str) or not VERSION_RE.fullmatch(data["version"]):
        fail("version must be semantic x.y.z")
    if not isinstance(data["core_api"], str) or not 1 <= len(data["core_api"]) <= 64:
        fail("invalid core_api range")
    if data["edition"] not in EDITIONS:
        fail("invalid edition")
    for field in ("entitlements", "capabilities"):
        if not isinstance(data[field], list) or len(data[field]) != len(set(data[field])):
            fail(f"{field} must be a unique array")
    if any(not isinstance(item, str) or len(item) > 128 or not TOKEN_RE.fullmatch(item) for item in data["entitlements"]):
        fail("invalid entitlement")
    if not set(data["capabilities"]).issubset(CAPABILITIES):
        fail("unknown capability")
    entrypoints = data["entrypoints"]
    if not isinstance(entrypoints, dict) or set(entrypoints) - {"admin"}:
        fail("invalid entrypoints")
    admin = entrypoints.get("admin")
    if admin is not None and (not isinstance(admin, str) or not ADMIN_RE.fullmatch(admin) or ".." in admin):
        fail("invalid admin entrypoint")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} MANIFEST.json", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        validate(json.loads(path.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"INVALID: {exc}", file=sys.stderr)
        return 1
    print(f"VALID: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
