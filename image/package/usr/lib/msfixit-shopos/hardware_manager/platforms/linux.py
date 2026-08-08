from __future__ import annotations

import os
import platform
from pathlib import Path

from hardware_manager.models import Capability, PlatformInfo
from .base import PlatformAdapter, read_text, run_command


class LinuxAdapter(PlatformAdapter):
    family = "linux"

    @staticmethod
    def _os_release() -> dict[str, str]:
        data: dict[str, str] = {}
        text = read_text("/etc/os-release") or ""
        for raw in text.splitlines():
            if not raw or raw.startswith("#") or "=" not in raw:
                continue
            key, value = raw.split("=", 1)
            if not key.replace("_", "").isalnum():
                continue
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            data[key] = value.replace("\\n", " ").replace("\\\"", "\"")[:256]
        return data

    @staticmethod
    def _cpu_model() -> str:
        text = read_text("/proc/cpuinfo") or ""
        preferred = ("model name", "Model", "Processor", "Hardware")
        values: dict[str, str] = {}
        for line in text.splitlines():
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            key = key.strip()
            value = value.strip()
            if key in preferred and value and key not in values:
                values[key] = value[:256]
        for key in preferred:
            if key in values:
                return values[key]
        return platform.processor() or "unknown"

    @staticmethod
    def _physical_cores() -> int | None:
        topology = Path("/sys/devices/system/cpu")
        pairs: set[tuple[str, str]] = set()
        try:
            cpu_dirs = sorted(topology.glob("cpu[0-9]*"))
        except OSError:
            return None
        for cpu_dir in cpu_dirs:
            package_id = read_text(cpu_dir / "topology/physical_package_id")
            core_id = read_text(cpu_dir / "topology/core_id")
            if package_id is not None and core_id is not None:
                pairs.add((package_id, core_id))
        return len(pairs) or None

    @staticmethod
    def _virtualization() -> str | None:
        marker = read_text("/run/systemd/container")
        if marker and len(marker) <= 64:
            return marker
        detected = run_command(["/usr/bin/systemd-detect-virt"], timeout=2.0)
        if detected and detected not in {"none", ""} and len(detected) <= 64:
            return detected
        return None

    def platform_info(self) -> PlatformInfo:
        release = self._os_release()
        logical = os.cpu_count() or 1
        return PlatformInfo(
            os_name="Linux",
            distribution=release.get("PRETTY_NAME") or release.get("NAME") or "Linux",
            distribution_version=release.get("VERSION_ID") or release.get("VERSION") or "unknown",
            kernel=platform.release() or "unknown",
            architecture=platform.machine() or "unknown",
            cpu_model=self._cpu_model(),
            logical_cpus=logical,
            physical_cores=self._physical_cores(),
            platform_family=self.family,
            virtualization=self._virtualization(),
        )

    def capabilities(self) -> dict[str, Capability]:
        thermal = Path("/sys/class/thermal").exists() or Path("/sys/class/hwmon").exists()
        return {
            "temperature": Capability("available" if thermal else "unavailable", "Kernel thermal/hwmon" if thermal else "Keine Thermal-/hwmon-Schnittstelle gefunden."),
            "undervoltage": Capability("unsupported", "Generisches Linux stellt keinen standardisierten Undervoltage-Status bereit."),
            "gpio": Capability("unavailable", "Keine plattformunabhängige GPIO-Aussage."),
            "i2c": Capability("available" if Path("/sys/bus/i2c/devices").exists() else "unavailable"),
            "spi": Capability("available" if Path("/sys/bus/spi/devices").exists() else "unavailable"),
            "printers": Capability("available", "Lokale CUPS-Drucker werden passiv über lpstat erfasst, falls verfügbar."),
        }
