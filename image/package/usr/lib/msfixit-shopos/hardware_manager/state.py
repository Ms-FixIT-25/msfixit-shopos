from __future__ import annotations

from collections import deque
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
from typing import Any

from hardware_manager.models import OperatingMode, Snapshot


@dataclass(slots=True)
class Settings:
    mode: OperatingMode = "observe"
    sample_interval_seconds: int = 30
    persist_interval_seconds: int = 300
    history_samples: int = 120
    emergency_shutdown_enabled: bool = False

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "Settings":
        mode = str(raw.get("mode", "observe"))
        if mode not in {"observe", "recommend", "automatic"}:
            mode = "observe"
        sample = raw.get("sample_interval_seconds", 30)
        persist = raw.get("persist_interval_seconds", 300)
        history = raw.get("history_samples", 120)
        try:
            sample_i = max(10, min(300, int(sample)))
            persist_i = max(60, min(3600, int(persist)))
            history_i = max(20, min(720, int(history)))
        except (TypeError, ValueError):
            sample_i, persist_i, history_i = 30, 300, 120
        shutdown = raw.get("emergency_shutdown_enabled", False) is True
        return cls(
            mode=mode,  # type: ignore[arg-type]
            sample_interval_seconds=sample_i,
            persist_interval_seconds=persist_i,
            history_samples=history_i,
            emergency_shutdown_enabled=shutdown,
        )


class StateStore:
    def __init__(self, state_dir: str | Path) -> None:
        self.state_dir = Path(state_dir)
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.settings_path = self.state_dir / "settings.json"
        self.snapshot_path = self.state_dir / "snapshot.json"
        self.settings = self._load_settings()
        self.history: deque[dict[str, Any]] = deque(maxlen=self.settings.history_samples)
        self.events: deque[dict[str, Any]] = deque(maxlen=500)
        self.latest: Snapshot | None = None

    def _load_settings(self) -> Settings:
        try:
            raw = json.loads(self.settings_path.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                return Settings.from_dict(raw)
        except (OSError, json.JSONDecodeError):
            pass
        settings = Settings()
        self._atomic_json(self.settings_path, asdict(settings))
        return settings

    def update_settings(self, raw: dict[str, Any]) -> Settings:
        merged = asdict(self.settings)
        for key in merged:
            if key in raw:
                merged[key] = raw[key]
        self.settings = Settings.from_dict(merged)
        if self.history.maxlen != self.settings.history_samples:
            self.history = deque(self.history, maxlen=self.settings.history_samples)
        self._atomic_json(self.settings_path, asdict(self.settings))
        return self.settings

    def set_snapshot(self, snapshot: Snapshot, *, persist: bool) -> None:
        self.latest = snapshot
        compact = {
            "timestamp": snapshot.timestamp,
            "cpu": asdict(snapshot.cpu),
            "memory": asdict(snapshot.memory),
            "thermal": {
                "primary_c": snapshot.thermal.primary_c,
                "level": snapshot.thermal.level,
                "current_throttling": snapshot.thermal.current_throttling,
                "current_undervoltage": snapshot.thermal.current_undervoltage,
            },
            "storage": {
                "free_bytes": snapshot.storage.free_bytes,
                "total_bytes": snapshot.storage.total_bytes,
            },
        }
        self.history.append(compact)
        if persist:
            self._atomic_json(self.snapshot_path, snapshot.as_dict())

    def add_event(self, kind: str, severity: str, message: str, **details: Any) -> None:
        safe_details: dict[str, Any] = {}
        for key, value in details.items():
            if isinstance(value, (str, int, float, bool)) or value is None:
                safe_details[key[:64]] = value
        self.events.append({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "kind": kind[:64],
            "severity": severity[:16],
            "message": message[:512],
            "details": safe_details,
        })

    @staticmethod
    def _atomic_json(path: Path, payload: Any) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(path.name + f".tmp-{os.getpid()}")
        data = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open(tmp, flags, 0o640)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(data)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        os.replace(tmp, path)
