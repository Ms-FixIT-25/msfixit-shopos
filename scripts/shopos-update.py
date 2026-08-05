#!/usr/bin/env python3
"""Fail-closed ShopOS A/B update manifest verifier and slot state machine."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Any

ALLOWED_PAYLOAD_KEYS = {
    "schema", "version", "sequence", "image_url", "image_sha256",
    "image_size", "target", "minimum_sequence", "issued_at", "expires_at",
}
ALLOWED_ENVELOPE_KEYS = {"payload", "signature"}
ALLOWED_STATES = {"idle", "staged", "trial", "confirmed", "rollback"}
ALLOWED_SLOTS = {"A", "B"}


class UpdateError(RuntimeError):
    pass


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def load_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise UpdateError(f"cannot read valid JSON: {path}") from exc
    if not isinstance(value, dict):
        raise UpdateError("JSON document must be an object")
    return value


def validate_payload(payload: dict[str, Any]) -> None:
    if set(payload) != ALLOWED_PAYLOAD_KEYS:
        raise UpdateError("manifest payload fields do not match the strict schema")
    if payload["schema"] != 1:
        raise UpdateError("unsupported manifest schema")
    if not isinstance(payload["version"], str) or not payload["version"]:
        raise UpdateError("invalid version")
    if not isinstance(payload["sequence"], int) or payload["sequence"] < 1:
        raise UpdateError("invalid sequence")
    if not isinstance(payload["minimum_sequence"], int) or payload["minimum_sequence"] < 0:
        raise UpdateError("invalid minimum sequence")
    if payload["minimum_sequence"] > payload["sequence"]:
        raise UpdateError("minimum sequence exceeds release sequence")
    if payload["target"] != "rpi4-usb":
        raise UpdateError("manifest target is not supported by this runtime")
    digest = payload["image_sha256"]
    if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise UpdateError("invalid image SHA-256")
    if not isinstance(payload["image_size"], int) or payload["image_size"] < 1:
        raise UpdateError("invalid image size")
    if not isinstance(payload["image_url"], str) or not payload["image_url"].startswith("https://"):
        raise UpdateError("image URL must use HTTPS")
    for key in ("issued_at", "expires_at"):
        if not isinstance(payload[key], str) or len(payload[key]) < 20:
            raise UpdateError(f"invalid {key}")


def verify_signature(payload: dict[str, Any], signature_b64: str, public_key: pathlib.Path) -> None:
    try:
        signature = base64.b64decode(signature_b64, validate=True)
    except Exception as exc:
        raise UpdateError("signature is not valid base64") from exc
    if len(signature) != 64:
        raise UpdateError("Ed25519 signature must be 64 bytes")
    if not public_key.is_file() or public_key.is_symlink():
        raise UpdateError("trusted update public key is unavailable")
    with tempfile.TemporaryDirectory(prefix="shopos-update-") as tmp:
        tmp_path = pathlib.Path(tmp)
        payload_path = tmp_path / "payload.json"
        signature_path = tmp_path / "signature.bin"
        payload_path.write_bytes(canonical_json(payload))
        signature_path.write_bytes(signature)
        result = subprocess.run(
            ["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", str(public_key),
             "-rawin", "-in", str(payload_path), "-sigfile", str(signature_path)],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            check=False, timeout=15,
        )
    if result.returncode != 0:
        raise UpdateError("manifest signature verification failed")


def verify_manifest(path: pathlib.Path, public_key: pathlib.Path) -> dict[str, Any]:
    envelope = load_json(path)
    if set(envelope) != ALLOWED_ENVELOPE_KEYS:
        raise UpdateError("manifest envelope fields do not match the strict schema")
    payload = envelope.get("payload")
    signature = envelope.get("signature")
    if not isinstance(payload, dict) or not isinstance(signature, str):
        raise UpdateError("invalid manifest envelope")
    validate_payload(payload)
    verify_signature(payload, signature, public_key)
    return payload


def default_state() -> dict[str, Any]:
    return {
        "schema": 1,
        "state": "idle",
        "active_slot": "A",
        "previous_slot": None,
        "target_slot": None,
        "installed_sequence": 0,
        "pending_sequence": None,
        "boot_attempts": 0,
        "max_boot_attempts": 3,
    }


def validate_state(state: dict[str, Any]) -> None:
    expected = set(default_state())
    if set(state) != expected or state["schema"] != 1:
        raise UpdateError("invalid update state schema")
    if state["state"] not in ALLOWED_STATES or state["active_slot"] not in ALLOWED_SLOTS:
        raise UpdateError("invalid update state")
    for key in ("previous_slot", "target_slot"):
        if state[key] is not None and state[key] not in ALLOWED_SLOTS:
            raise UpdateError("invalid slot in update state")
    if not isinstance(state["installed_sequence"], int) or state["installed_sequence"] < 0:
        raise UpdateError("invalid installed sequence")
    if state["pending_sequence"] is not None and (not isinstance(state["pending_sequence"], int) or state["pending_sequence"] < 1):
        raise UpdateError("invalid pending sequence")
    if not isinstance(state["boot_attempts"], int) or state["boot_attempts"] < 0:
        raise UpdateError("invalid boot attempts")
    if not isinstance(state["max_boot_attempts"], int) or not 1 <= state["max_boot_attempts"] <= 10:
        raise UpdateError("invalid maximum boot attempts")


def load_state(path: pathlib.Path) -> dict[str, Any]:
    if not path.exists():
        return default_state()
    state = load_json(path)
    validate_state(state)
    return state


def atomic_write(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    data = canonical_json(value) + b"\n"
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
        dir_fd = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def inactive_slot(active: str) -> str:
    return "B" if active == "A" else "A"


def stage(state: dict[str, Any], payload: dict[str, Any]) -> dict[str, Any]:
    if state["state"] not in {"idle", "confirmed"}:
        raise UpdateError("another update transaction is already active")
    sequence = payload["sequence"]
    if sequence <= state["installed_sequence"]:
        raise UpdateError("downgrade or replay is not allowed")
    if state["installed_sequence"] < payload["minimum_sequence"]:
        raise UpdateError("installed version is below the supported migration floor")
    state.update({
        "state": "staged",
        "previous_slot": state["active_slot"],
        "target_slot": inactive_slot(state["active_slot"]),
        "pending_sequence": sequence,
        "boot_attempts": 0,
    })
    return state


def activate_trial(state: dict[str, Any]) -> dict[str, Any]:
    if state["state"] != "staged" or state["target_slot"] is None:
        raise UpdateError("no staged update is available")
    state["active_slot"] = state["target_slot"]
    state["state"] = "trial"
    state["boot_attempts"] = 0
    return state


def record_boot(state: dict[str, Any]) -> dict[str, Any]:
    if state["state"] != "trial":
        return state
    state["boot_attempts"] += 1
    if state["boot_attempts"] >= state["max_boot_attempts"]:
        if state["previous_slot"] is None:
            raise UpdateError("rollback slot is unavailable")
        state["active_slot"] = state["previous_slot"]
        state["state"] = "rollback"
    return state


def confirm(state: dict[str, Any]) -> dict[str, Any]:
    if state["state"] != "trial" or state["pending_sequence"] is None:
        raise UpdateError("no trial update can be confirmed")
    state.update({
        "state": "confirmed",
        "installed_sequence": state["pending_sequence"],
        "previous_slot": None,
        "target_slot": None,
        "pending_sequence": None,
        "boot_attempts": 0,
    })
    return state


def reset_after_rollback(state: dict[str, Any]) -> dict[str, Any]:
    if state["state"] != "rollback":
        raise UpdateError("system is not in rollback state")
    state.update({
        "state": "idle",
        "previous_slot": None,
        "target_slot": None,
        "pending_sequence": None,
        "boot_attempts": 0,
    })
    return state


def hash_image(path: pathlib.Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=pathlib.Path, default=pathlib.Path("/var/lib/msfixit-shopos/update/state.json"))
    parser.add_argument("--public-key", type=pathlib.Path, default=pathlib.Path("/usr/share/msfixit-shopos/update/update-signing-public.pem"))
    sub = parser.add_subparsers(dest="command", required=True)
    verify = sub.add_parser("verify")
    verify.add_argument("manifest", type=pathlib.Path)
    verify.add_argument("--image", type=pathlib.Path)
    stage_cmd = sub.add_parser("stage")
    stage_cmd.add_argument("manifest", type=pathlib.Path)
    sub.add_parser("activate-trial")
    sub.add_parser("record-boot")
    sub.add_parser("confirm")
    sub.add_parser("reset-rollback")
    sub.add_parser("status")
    args = parser.parse_args()
    try:
        if args.command == "verify":
            payload = verify_manifest(args.manifest, args.public_key)
            if args.image:
                digest, size = hash_image(args.image)
                if digest != payload["image_sha256"] or size != payload["image_size"]:
                    raise UpdateError("image digest or size does not match the signed manifest")
            print(json.dumps(payload, sort_keys=True))
            return 0
        state = load_state(args.state)
        if args.command == "stage":
            state = stage(state, verify_manifest(args.manifest, args.public_key))
        elif args.command == "activate-trial":
            state = activate_trial(state)
        elif args.command == "record-boot":
            state = record_boot(state)
        elif args.command == "confirm":
            state = confirm(state)
        elif args.command == "reset-rollback":
            state = reset_after_rollback(state)
        elif args.command == "status":
            print(json.dumps(state, sort_keys=True))
            return 0
        validate_state(state)
        atomic_write(args.state, state)
        print(json.dumps(state, sort_keys=True))
        return 0
    except (UpdateError, OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
