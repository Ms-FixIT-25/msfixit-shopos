#!/usr/bin/env python3
"""Verify signed ShopOS licenses and query effective entitlements."""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ALLOWED_FIELDS = {
    "schema", "license_id", "customer_id", "edition", "entitlements",
    "issued_at", "expires_at", "installations", "developer", "signature"
}
EDITIONS = {"community", "professional", "enterprise", "developer"}


def canonical_payload(data: dict) -> bytes:
    payload = {k: v for k, v in data.items() if k != "signature"}
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def parse_time(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamps must include timezone")
    return parsed.astimezone(dt.timezone.utc)


def validate_document(data: object, now: dt.datetime) -> dict:
    if not isinstance(data, dict):
        raise ValueError("license must be a JSON object")
    unknown = set(data) - ALLOWED_FIELDS
    if unknown:
        raise ValueError(f"unknown fields: {', '.join(sorted(unknown))}")
    required = {"schema", "license_id", "customer_id", "edition", "entitlements", "issued_at", "installations", "developer", "signature"}
    missing = required - set(data)
    if missing:
        raise ValueError(f"missing fields: {', '.join(sorted(missing))}")
    if data["schema"] != 1:
        raise ValueError("schema must be 1")
    if data["edition"] not in EDITIONS:
        raise ValueError("invalid edition")
    if data["edition"] == "developer" and data["developer"] is not True:
        raise ValueError("developer edition requires developer=true")
    if data["edition"] != "developer" and data["developer"] is not False:
        raise ValueError("customer licenses require developer=false")
    if not isinstance(data["entitlements"], list) or len(data["entitlements"]) != len(set(data["entitlements"])):
        raise ValueError("entitlements must be a unique array")
    if not isinstance(data["installations"], int) or data["installations"] < 1:
        raise ValueError("installations must be a positive integer")
    issued = parse_time(data["issued_at"])
    if issued > now + dt.timedelta(minutes=5):
        raise ValueError("license is not yet valid")
    if data.get("expires_at") is not None and parse_time(data["expires_at"]) < now:
        raise ValueError("license expired")
    if not isinstance(data["signature"], str) or not data["signature"]:
        raise ValueError("signature missing")
    return data


def verify_signature(data: dict, public_key: Path) -> None:
    try:
        signature = base64.b64decode(data["signature"], validate=True)
    except Exception as exc:
        raise ValueError("signature is not valid base64") from exc
    with tempfile.TemporaryDirectory() as tmp:
        payload_path = Path(tmp) / "payload.json"
        sig_path = Path(tmp) / "signature.bin"
        payload_path.write_bytes(canonical_payload(data))
        sig_path.write_bytes(signature)
        result = subprocess.run(
            ["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", str(public_key), "-rawin", "-in", str(payload_path), "-sigfile", str(sig_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    if result.returncode != 0:
        raise ValueError("signature verification failed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("license", type=Path)
    parser.add_argument("--public-key", required=True, type=Path)
    parser.add_argument("--require-entitlement")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        data = json.loads(args.license.read_text(encoding="utf-8"))
        now = dt.datetime.now(dt.timezone.utc)
        license_data = validate_document(data, now)
        verify_signature(license_data, args.public_key)
        if args.require_entitlement and args.require_entitlement not in license_data["entitlements"]:
            raise ValueError("required entitlement is not granted")
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"INVALID: {exc}", file=sys.stderr)
        return 1
    result = {
        "valid": True,
        "license_id": license_data["license_id"],
        "edition": license_data["edition"],
        "developer": license_data["developer"],
        "entitlements": license_data["entitlements"],
    }
    print(json.dumps(result, sort_keys=True) if args.json else f"VALID: {result['edition']} {result['license_id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
