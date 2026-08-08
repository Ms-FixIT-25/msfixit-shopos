from __future__ import annotations

from dataclasses import dataclass
import time

from hardware_manager.models import ThermalLevel

_LEVELS: tuple[ThermalLevel, ...] = ("normal", "elevated", "warning", "critical", "emergency")


@dataclass(slots=True, frozen=True)
class ThermalPolicy:
    elevated_c: float
    warning_c: float
    critical_c: float
    emergency_c: float
    hysteresis_c: float = 3.0
    rise_samples: int = 3
    fall_samples: int = 5
    emergency_samples: int = 4
    emergency_min_seconds: int = 120
    shutdown_enabled: bool = False

    @classmethod
    def for_platform(cls, platform_family: str, model: str | None = None) -> "ThermalPolicy":
        model_lower = (model or "").lower()
        if platform_family == "raspberry-pi":
            return cls(60.0, 70.0, 78.0, 83.0)
        if "server" in model_lower:
            return cls(65.0, 75.0, 85.0, 92.0)
        return cls(65.0, 75.0, 85.0, 92.0)


@dataclass(slots=True)
class ThermalDecision:
    level: ThermalLevel
    changed: bool
    previous_level: ThermalLevel
    primary_c: float | None
    plausible: bool
    consecutive_high: int
    consecutive_low: int
    emergency_seconds: int
    shutdown_eligible: bool
    reason: str


class ThermalStateMachine:
    def __init__(self, policy: ThermalPolicy) -> None:
        self.policy = policy
        self.level: ThermalLevel = "normal"
        self._candidate: ThermalLevel = "normal"
        self._rise_count = 0
        self._fall_count = 0
        self._emergency_since: float | None = None

    def _raw_level(self, temperature_c: float) -> ThermalLevel:
        if temperature_c >= self.policy.emergency_c:
            return "emergency"
        if temperature_c >= self.policy.critical_c:
            return "critical"
        if temperature_c >= self.policy.warning_c:
            return "warning"
        if temperature_c >= self.policy.elevated_c:
            return "elevated"
        return "normal"

    @staticmethod
    def _rank(level: ThermalLevel) -> int:
        return _LEVELS.index(level)

    def update(self, temperature_c: float | None, *, now: float | None = None) -> ThermalDecision:
        timestamp = time.monotonic() if now is None else now
        previous = self.level
        plausible = temperature_c is not None and -20.0 <= temperature_c <= 130.0
        if not plausible:
            self._rise_count = 0
            self._fall_count = 0
            return ThermalDecision(
                level=self.level,
                changed=False,
                previous_level=previous,
                primary_c=temperature_c,
                plausible=False,
                consecutive_high=0,
                consecutive_low=0,
                emergency_seconds=self._emergency_seconds(timestamp),
                shutdown_eligible=False,
                reason="Temperatursensor liefert keinen plausiblen Wert; keine automatische Schutzaktion.",
            )

        assert temperature_c is not None
        raw = self._raw_level(temperature_c)
        current_rank = self._rank(self.level)
        raw_rank = self._rank(raw)
        changed = False
        reason = "Temperatur stabil."

        if raw_rank > current_rank:
            if raw != self._candidate:
                self._candidate = raw
                self._rise_count = 1
            else:
                self._rise_count += 1
            self._fall_count = 0
            required = self.policy.emergency_samples if raw == "emergency" else self.policy.rise_samples
            if self._rise_count >= required:
                self.level = raw
                changed = self.level != previous
                self._rise_count = 0
                self._candidate = self.level
                reason = f"Temperaturstufe nach {required} bestätigten Messungen erhöht."
        elif raw_rank < current_rank:
            threshold = {
                "emergency": self.policy.emergency_c,
                "critical": self.policy.critical_c,
                "warning": self.policy.warning_c,
                "elevated": self.policy.elevated_c,
                "normal": -273.0,
            }[self.level]
            if temperature_c <= threshold - self.policy.hysteresis_c:
                self._fall_count += 1
            else:
                self._fall_count = 0
            self._rise_count = 0
            self._candidate = self.level
            if self._fall_count >= self.policy.fall_samples:
                self.level = raw
                changed = self.level != previous
                self._fall_count = 0
                reason = "Temperaturstufe nach Hysterese und mehreren kühleren Messungen reduziert."
        else:
            self._rise_count = 0
            self._fall_count = 0
            self._candidate = self.level

        if self.level == "emergency":
            if self._emergency_since is None:
                self._emergency_since = timestamp
        else:
            self._emergency_since = None

        emergency_seconds = self._emergency_seconds(timestamp)
        shutdown_eligible = bool(
            self.policy.shutdown_enabled
            and self.level == "emergency"
            and emergency_seconds >= self.policy.emergency_min_seconds
            and temperature_c >= self.policy.emergency_c
        )
        if shutdown_eligible:
            reason = "Notfalltemperatur blieb über die Mindestdauer bestätigt; geregeltes Herunterfahren ist zulässig."

        return ThermalDecision(
            level=self.level,
            changed=changed,
            previous_level=previous,
            primary_c=temperature_c,
            plausible=True,
            consecutive_high=self._rise_count,
            consecutive_low=self._fall_count,
            emergency_seconds=emergency_seconds,
            shutdown_eligible=shutdown_eligible,
            reason=reason,
        )

    def _emergency_seconds(self, now: float) -> int:
        if self._emergency_since is None:
            return 0
        return max(0, int(now - self._emergency_since))
