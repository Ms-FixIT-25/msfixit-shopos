#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
from typing import Any

ALLOWED_PAYLOAD_KEYS = {
    "schema", "version", "sequence", "image_url", "image_sha256",
    "image_size", "target", "minimum_sequence", "issued_at", "expires_at",
}


def fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def verify(manifest_path: pathlib.Path, public_key: pathlib.Path, image_path: pathlib.Path | None) -> dict[str, Any]:
    if not public_key.is_file() or public_key.is_symlink():
        raise ValueError("trusted update public key is unavailable")
    envelope = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(envelope, dict) or set(envelope) != {"payload", "signature"}:
        raise ValueError("manifest envelope fields do not match the strict schema")
    payload = envelope["payload"]
    signature_b64 = envelope["signature"]
    if not isinstance(payload, dict) or set(payload) != ALLOWED_PAYLOAD_KEYS:
        raise ValueError("manifest payload fields do not match the strict schema")
    if payload.get("schema") != 1 or payload.get("target") != "rpi4-usb":
        raise ValueError("unsupported update schema or target")
    if not isinstance(payload.get("version"), str) or not payload["version"]:
        raise ValueError("invalid version")
    if not isinstance(payload.get("sequence"), int) or payload["sequence"] < 1:
        raise ValueError("invalid sequence")
    if not isinstance(payload.get("minimum_sequence"), int) or payload["minimum_sequence"] < 0:
        raise ValueError("invalid minimum sequence")
    if payload["minimum_sequence"] > payload["sequence"]:
        raise ValueError("minimum sequence exceeds release sequence")
    image_url = payload.get("image_url")
    if not isinstance(image_url, str) or not image_url.startswith("https://"):
        raise ValueError("image URL must use HTTPS")
    digest = payload.get("image_sha256")
    if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise ValueError("invalid image SHA-256")
    if not isinstance(payload.get("image_size"), int) or payload["image_size"] < 1:
        raise ValueError("invalid image size")
    if not isinstance(signature_b64, str):
        raise ValueError("invalid signature")
    signature = base64.b64decode(signature_b64, validate=True)
    if len(signature) != 64:
        raise ValueError("Ed25519 signature must be 64 bytes")

    with tempfile.TemporaryDirectory(prefix="shopos-install-update-") as tmp:
        tmp_path = pathlib.Path(tmp)
        payload_file = tmp_path / "payload.json"
        signature_file = tmp_path / "signature.bin"
        payload_file.write_bytes(canonical_json(payload))
        signature_file.write_bytes(signature)
        result = subprocess.run(
            ["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", str(public_key),
             "-rawin", "-in", str(payload_file), "-sigfile", str(signature_file)],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            check=False, timeout=15,
        )
    if result.returncode != 0:
        raise ValueError("manifest signature verification failed")

    if image_path is not None:
        h = hashlib.sha256()
        size = 0
        with image_path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                h.update(chunk)
                size += len(chunk)
        if h.hexdigest() != digest or size != payload["image_size"]:
            raise ValueError("image digest or size does not match signed manifest")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--public-key", required=True, type=pathlib.Path)
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("--image", type=pathlib.Path)
    args = parser.parse_args()
    try:
        payload = verify(args.manifest, args.public_key, args.image)
    except (OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError, base64.binascii.Error) as exc:
        return fail(str(exc))
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
