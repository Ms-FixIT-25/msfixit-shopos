#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path

ALLOWED_PACKAGE_FIELDS = {"schema", "app_id", "version", "manifest_sha256", "payload_sha256", "signature"}
APP_ID_RE = re.compile(r"^at\.msfixit\.shopos\.[a-z0-9]+(?:[.-][a-z0-9]+)*$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise ValueError(message)


def canonical(data: dict) -> bytes:
    return json.dumps({key: value for key, value in data.items() if key != "signature"}, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def verify_signature(meta: dict, key: Path) -> None:
    if not key.is_file() or key.is_symlink():
        fail("public key must be a regular non-symlink file")
    try:
        signature = base64.b64decode(meta["signature"], validate=True)
    except Exception as exc:
        raise ValueError("invalid signature encoding") from exc
    if len(signature) != 64:
        fail("invalid Ed25519 signature length")
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp)
        (path / "payload").write_bytes(canonical(meta))
        (path / "sig").write_bytes(signature)
        result = subprocess.run(["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", str(key), "-rawin", "-in", str(path / "payload"), "-sigfile", str(path / "sig")], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False, timeout=15)
    if result.returncode:
        fail("signature verification failed")


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def safe_extract(archive: tarfile.TarFile, target: Path) -> None:
    root = target.resolve()
    for member in archive.getmembers():
        if not (member.isfile() or member.isdir()):
            fail(f"unsupported archive member type: {member.name}")
        if member.mode & (stat.S_ISUID | stat.S_ISGID):
            fail(f"set-id archive member is forbidden: {member.name}")
        destination = (target / member.name).resolve()
        if destination != root and root not in destination.parents:
            fail("path traversal detected")
    archive.extractall(target, filter="data")


def load_manifest(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail("manifest must be an object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--public-key", required=True, type=Path)
    parser.add_argument("--root", type=Path, default=Path("/var/lib/msfixit-shopos/apps"))
    parser.add_argument("--audit", type=Path, default=Path("/var/log/msfixit-shopos/app-install.jsonl"))
    parser.add_argument("--fail-after-stage", action="store_true")
    args = parser.parse_args()
    try:
        if not args.package.is_file() or args.package.is_symlink():
            fail("package must be a regular non-symlink file")
        with tempfile.TemporaryDirectory(prefix="shopos-app-") as temp:
            stage = Path(temp)
            with tarfile.open(args.package, "r:*") as package_archive:
                safe_extract(package_archive, stage)
            meta = json.loads((stage / "package.json").read_text(encoding="utf-8"))
            if not isinstance(meta, dict) or set(meta) != ALLOWED_PACKAGE_FIELDS or meta.get("schema") != 1:
                fail("invalid package metadata")
            app_id = meta.get("app_id")
            version = meta.get("version")
            if not isinstance(app_id, str) or not APP_ID_RE.fullmatch(app_id):
                fail("invalid signed app id")
            if not isinstance(version, str) or not VERSION_RE.fullmatch(version):
                fail("invalid signed app version")
            for field in ("manifest_sha256", "payload_sha256"):
                if not isinstance(meta.get(field), str) or not SHA256_RE.fullmatch(meta[field]):
                    fail(f"invalid {field}")
            manifest = stage / "manifest.json"
            payload = stage / "payload.tar"
            if not manifest.is_file() or manifest.is_symlink() or not payload.is_file() or payload.is_symlink():
                fail("package manifest and payload must be regular files")
            if digest(manifest) != meta["manifest_sha256"] or digest(payload) != meta["payload_sha256"]:
                fail("package digest mismatch")
            verify_signature(meta, args.public_key)
            validator = Path(__file__).with_name("validate-shopos-app.py")
            subprocess.run([sys.executable, str(validator), str(manifest)], stdin=subprocess.DEVNULL, check=True, timeout=30)
            manifest_data = load_manifest(manifest)
            if manifest_data.get("id") != app_id:
                fail("signed app_id does not match manifest id")
            if manifest_data.get("version") != version:
                fail("signed version does not match manifest version")
            app_stage = stage / "app"
            app_stage.mkdir()
            with tarfile.open(payload, "r:") as payload_archive:
                safe_extract(payload_archive, app_stage)
            if args.fail_after_stage:
                fail("simulated failure")
            args.root.mkdir(parents=True, exist_ok=True)
            target = args.root / app_id
            backup = args.root / (app_id + ".rollback")
            if backup.exists():
                shutil.rmtree(backup)
            if target.exists():
                os.replace(target, backup)
            try:
                os.replace(app_stage, target)
            except Exception:
                if backup.exists():
                    os.replace(backup, target)
                raise
            if backup.exists():
                shutil.rmtree(backup)
            args.audit.parent.mkdir(parents=True, exist_ok=True)
            with args.audit.open("a", encoding="utf-8") as log:
                log.write(json.dumps({"time": int(time.time()), "action": "install", "app_id": app_id, "version": version, "result": "success"}, sort_keys=True) + "\n")
            print(f"INSTALLED: {app_id} {version}")
            return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError, tarfile.TarError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
