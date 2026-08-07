from __future__ import annotations

import json
import os
from pathlib import Path
import socketserver
import stat
from typing import Any, Protocol

from hardware_manager import API_VERSION

MAX_REQUEST_BYTES = 64 * 1024


class ApiBackend(Protocol):
    def api_request(self, request: dict[str, Any]) -> dict[str, Any]: ...


class _RequestHandler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        raw = self.rfile.readline(MAX_REQUEST_BYTES + 1)
        if len(raw) > MAX_REQUEST_BYTES:
            self._reply({"ok": False, "error": "request_too_large"})
            return
        try:
            request = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._reply({"ok": False, "error": "invalid_json"})
            return
        if not isinstance(request, dict):
            self._reply({"ok": False, "error": "invalid_request"})
            return
        if request.get("api") != API_VERSION:
            self._reply({"ok": False, "error": "unsupported_api_version", "api": API_VERSION})
            return
        method = request.get("method")
        path = request.get("path")
        if method not in {"GET", "POST"} or not isinstance(path, str) or len(path) > 128:
            self._reply({"ok": False, "error": "invalid_request"})
            return
        try:
            response = self.server.backend.api_request(request)  # type: ignore[attr-defined]
        except Exception:
            response = {"ok": False, "error": "internal_error"}
        self._reply(response)

    def _reply(self, payload: dict[str, Any]) -> None:
        payload.setdefault("api", API_VERSION)
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
        self.wfile.write(encoded + b"\n")
        self.wfile.flush()


class HardwareApiServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(self, path: str | Path, backend: ApiBackend) -> None:
        self.socket_path = Path(path)
        self.backend = backend
        self._prepare_path()
        super().__init__(str(self.socket_path), _RequestHandler)

    def _prepare_path(self) -> None:
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            st = os.lstat(self.socket_path)
        except FileNotFoundError:
            return
        if not stat.S_ISSOCK(st.st_mode) or st.st_uid != os.geteuid():
            raise RuntimeError("Refusing to replace unsafe API socket path")
        self.socket_path.unlink()

    def set_permissions(self, gid: int) -> None:
        os.chown(self.socket_path, -1, gid)
        os.chmod(self.socket_path, 0o660)

    def server_close(self) -> None:
        try:
            super().server_close()
        finally:
            try:
                self.socket_path.unlink()
            except FileNotFoundError:
                pass
