from __future__ import annotations

from dataclasses import asdict, replace
from datetime import datetime, timezone
import grp
import logging
import os
import threading
import time
from typing import Any

from hardware_manager.actions import apply_action, rollback_action, verify_admin_password
from hardware_manager.api import HardwareApiServer
from hardware_manager.models import Snapshot, ThermalSensor, ThermalSnapshot
from hardware_manager.platforms import select_adapter
from hardware_manager.rules import RuleEngine
from hardware_manager.sensors import SensorCollector
from hardware_manager.state import StateStore
from hardware_manager.thermal import ThermalPolicy, ThermalStateMachine

LOG = logging.getLogger("shopos-hardware-manager")


class HardwareManager:
    def __init__(self, *, state_dir: str = "/var/lib/msfixit-shopos/hardware-manager", socket_path: str = "/run/msfixit-hardware-manager/api.sock") -> None:
        self.adapter = select_adapter()
        self.platform = self.adapter.platform_info()
        self.capabilities = self.adapter.capabilities()
        self.store = StateStore(state_dir)
        policy = ThermalPolicy.for_platform(self.platform.platform_family, self.platform.model)
        policy = replace(policy, shutdown_enabled=self.store.settings.emergency_shutdown_enabled)
        self.thermal_machine = ThermalStateMachine(policy)
        self.collector = SensorCollector(self.platform.platform_family)
        self.rules = RuleEngine()
        self.socket_path = socket_path
        self._lock = threading.RLock()
        self._stop = threading.Event()
        self._last_persist = 0.0
        self._last_throttled_mask: int | None = None
        self._auto_cooldown: dict[str, float] = {}
        self._api: HardwareApiServer | None = None
        self._last_shutdown_eligible_event = 0.0

    def _primary_temperature(self, sensors: list[ThermalSensor]) -> float | None:
        if not sensors:
            return None
        preferred = ["cpu-thermal", "cpu_thermal", "soc_thermal", "soc"] if self.platform.platform_family == "raspberry-pi" else ["package", "cpu", "coretemp", "tctl", "tdie", "soc"]
        for needle in preferred:
            matches = [sensor for sensor in sensors if needle in sensor.label.lower()]
            if matches:
                return max(sensor.temperature_c for sensor in matches)
        if len(sensors) == 1:
            return sensors[0].temperature_c
        return None

    def _thermal_snapshot(self, sensors: list[ThermalSensor]) -> ThermalSnapshot:
        primary = self._primary_temperature(sensors)
        decision = self.thermal_machine.update(primary)
        mask = self.collector.raspberry_pi_throttled()
        current_undervoltage = bool(mask & 0x1) if mask is not None else None
        undervoltage_occurred = bool(mask & 0x10000) if mask is not None else None
        current_throttling = bool(mask & 0x4) if mask is not None else None
        throttling_occurred = bool(mask & 0x40000) if mask is not None else None
        if decision.changed:
            severity = "critical" if decision.level in {"critical", "emergency"} else "warning" if decision.level == "warning" else "info"
            self.store.add_event("thermal-state", severity, f"Temperaturstufe: {decision.previous_level} → {decision.level}", temperature_c=primary, reason=decision.reason)
            LOG.warning("thermal level changed %s -> %s at %s C", decision.previous_level, decision.level, primary)
        if mask is not None and mask != self._last_throttled_mask:
            if current_undervoltage:
                self.store.add_event("undervoltage", "critical", "Aktuelle Raspberry-Pi-Unterspannung erkannt.", mask=hex(mask))
                LOG.error("Raspberry Pi undervoltage detected mask=%s", hex(mask))
            elif undervoltage_occurred and self._last_throttled_mask is None:
                self.store.add_event("undervoltage-history", "warning", "Unterspannung ist seit diesem Start bereits aufgetreten.", mask=hex(mask))
            self._last_throttled_mask = mask
        if decision.shutdown_eligible:
            now = time.monotonic()
            if now - self._last_shutdown_eligible_event >= 60:
                self._last_shutdown_eligible_event = now
                self.store.add_event("emergency-shutdown-eligible", "critical", "Notfalltemperatur ist lang genug bestätigt; Hardware-Laborfreigabe für automatische Abschaltung fehlt noch.", temperature_c=primary, emergency_seconds=decision.emergency_seconds)
                LOG.critical("emergency shutdown eligible after %ss at %s C; automatic poweroff intentionally blocked pending real-hardware validation", decision.emergency_seconds, primary)
        return ThermalSnapshot(
            sensors=sensors,
            primary_c=primary,
            level=decision.level,
            current_throttling=current_throttling,
            throttling_occurred=throttling_occurred,
            current_undervoltage=current_undervoltage,
            undervoltage_occurred=undervoltage_occurred,
            raw_throttled_mask=mask,
            emergency_seconds=decision.emergency_seconds,
            shutdown_eligible=decision.shutdown_eligible,
            decision_reason=decision.reason,
        )

    def sample(self) -> Snapshot:
        with self._lock:
            cpu = self.collector.cpu()
            memory = self.collector.memory()
            thermal = self._thermal_snapshot(self.collector.thermal_sensors())
            storage = self.collector.storage()
            network = self.collector.network()
            usb = self.collector.usb()
            printers = self.collector.printers()
            services = self.collector.services()
            recommendations = self.rules.evaluate(platform_family=self.platform.platform_family, cpu=cpu, memory=memory, thermal=thermal, storage=storage, network=network, usb=usb, services=services)
            snapshot = Snapshot(
                timestamp=datetime.now(timezone.utc).isoformat(), platform=self.platform, cpu=cpu, memory=memory,
                thermal=thermal, storage=storage, network=network, usb=usb, printers=printers, services=services,
                recommendations=recommendations, capabilities=self.capabilities, mode=self.store.settings.mode,
            )
            now = time.monotonic()
            persist = now - self._last_persist >= self.store.settings.persist_interval_seconds
            self.store.set_snapshot(snapshot, persist=persist)
            if persist:
                self._last_persist = now
            self._apply_automatic_recommendations(snapshot, now)
            return snapshot

    def _apply_automatic_recommendations(self, snapshot: Snapshot, now: float) -> None:
        if self.store.settings.mode != "automatic":
            return
        for recommendation in snapshot.recommendations:
            if not recommendation.automatable or not recommendation.action_id or not recommendation.action_value:
                continue
            last = self._auto_cooldown.get(recommendation.id, 0.0)
            if now - last < 600:
                continue
            self._auto_cooldown[recommendation.id] = now
            result = apply_action(recommendation.action_id, recommendation.action_value)
            self.store.add_event("automatic-optimization", "info" if result.get("ok") else "warning", f"Automatische Optimierung {recommendation.id}: {'erfolgreich' if result.get('ok') else 'fehlgeschlagen'}.", transaction_id=result.get("transaction_id"), error=result.get("error"))
            LOG.info("automatic optimization %s result=%s", recommendation.id, result)

    @staticmethod
    def _require_password(request: dict[str, Any]) -> bool:
        password = request.get("password")
        return isinstance(password, str) and verify_admin_password(password)

    def api_request(self, request: dict[str, Any]) -> dict[str, Any]:
        method = request["method"]
        path = request["path"]
        with self._lock:
            if method == "GET" and path == "/health":
                return {"ok": True, "status": "running", "has_snapshot": self.store.latest is not None}
            if method == "GET" and path == "/status":
                return {"ok": True, "snapshot": self.store.latest.as_dict() if self.store.latest else None}
            if method == "GET" and path == "/history":
                return {"ok": True, "history": list(self.store.history)}
            if method == "GET" and path == "/events":
                return {"ok": True, "events": list(self.store.events)}
            if method == "GET" and path == "/recommendations":
                return {"ok": True, "recommendations": [asdict(item) for item in (self.store.latest.recommendations if self.store.latest else [])]}
            if method == "GET" and path == "/settings":
                return {"ok": True, "settings": asdict(self.store.settings)}
            if method == "GET" and path == "/diagnostic":
                return {"ok": True, "diagnostic": {"snapshot": self.store.latest.as_dict() if self.store.latest else None, "events": list(self.store.events), "settings": asdict(self.store.settings), "note": "Keine Passwörter, Tokens, IP- oder MAC-Adressen werden vom Hardware-Manager erfasst."}}
            if method != "POST":
                return {"ok": False, "error": "not_found"}
            if not self._require_password(request):
                return {"ok": False, "error": "authentication_failed"}
            if path == "/settings":
                body = request.get("body")
                if not isinstance(body, dict):
                    return {"ok": False, "error": "invalid_settings"}
                if body.get("emergency_shutdown_enabled") is True and body.get("confirm_emergency_shutdown") is not True:
                    return {"ok": False, "error": "emergency_confirmation_required"}
                settings = self.store.update_settings(body)
                policy = ThermalPolicy.for_platform(self.platform.platform_family, self.platform.model)
                self.thermal_machine.policy = replace(policy, shutdown_enabled=settings.emergency_shutdown_enabled)
                self.store.add_event("settings", "info", "Hardware-Manager-Einstellungen wurden geändert.", mode=settings.mode)
                return {"ok": True, "settings": asdict(settings), "automatic_shutdown_execution": False}
            if path == "/actions/apply":
                recommendation_id = request.get("recommendation_id")
                if not isinstance(recommendation_id, str) or len(recommendation_id) > 128 or self.store.latest is None:
                    return {"ok": False, "error": "invalid_recommendation"}
                recommendation = next((item for item in self.store.latest.recommendations if item.id == recommendation_id), None)
                if recommendation is None or not recommendation.action_id or not recommendation.action_value:
                    return {"ok": False, "error": "action_not_available"}
                result = apply_action(recommendation.action_id, recommendation.action_value)
                self.store.add_event("manual-optimization", "info" if result.get("ok") else "warning", f"Optimierung {recommendation.id}: {'erfolgreich' if result.get('ok') else 'fehlgeschlagen'}.", transaction_id=result.get("transaction_id"), error=result.get("error"))
                return result
            if path == "/actions/rollback":
                transaction_id = request.get("transaction_id")
                if not isinstance(transaction_id, str):
                    return {"ok": False, "error": "invalid_transaction"}
                result = rollback_action(transaction_id)
                self.store.add_event("rollback", "info" if result.get("ok") else "warning", f"Rollback {transaction_id}: {'erfolgreich' if result.get('ok') else 'fehlgeschlagen'}.", error=result.get("error"))
                return result
            return {"ok": False, "error": "not_found"}

    def start_api(self) -> threading.Thread:
        self._api = HardwareApiServer(self.socket_path, self)
        try:
            gid = grp.getgrnam("shopos-hwapi").gr_gid
        except KeyError:
            gid = os.getgid()
        self._api.set_permissions(gid)
        thread = threading.Thread(target=self._api.serve_forever, name="hardware-api", daemon=True)
        thread.start()
        return thread

    def run(self) -> None:
        LOG.info("starting ShopOS Hardware Manager platform=%s model=%s", self.platform.platform_family, self.platform.model)
        self.sample()
        self.start_api()
        while not self._stop.wait(self.store.settings.sample_interval_seconds):
            try:
                self.sample()
            except Exception:
                LOG.exception("hardware sample failed")
                self.store.add_event("sampling-error", "warning", "Eine Hardwaremessung ist fehlgeschlagen; der Dienst läuft weiter.")

    def stop(self) -> None:
        self._stop.set()
        if self._api is not None:
            self._api.shutdown()
            self._api.server_close()
