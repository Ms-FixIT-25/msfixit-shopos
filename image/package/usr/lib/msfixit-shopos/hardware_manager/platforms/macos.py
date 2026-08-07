from __future__ import annotations

import os
import platform

from hardware_manager.models import Capability, PlatformInfo
from .base import PlatformAdapter, run_command


class MacOSAdapter(PlatformAdapter):
    family = "macos"

    @staticmethod
    def _sysctl(name: str) -> str | None:
        allowed = {
            "machdep.cpu.brand_string",
            "hw.model",
            "hw.physicalcpu",
            "hw.logicalcpu",
        }
        if name not in allowed:
            return None
        return run_command(["/usr/sbin/sysctl", "-n", name])

    def platform_info(self) -> PlatformInfo:
        arch = platform.machine() or "unknown"
        apple_silicon = arch in {"arm64", "aarch64"}
        cpu_model = self._sysctl("machdep.cpu.brand_string")
        if not cpu_model and apple_silicon:
            cpu_model = self._sysctl("hw.model") or "Apple Silicon"
        physical_raw = self._sysctl("hw.physicalcpu")
        logical_raw = self._sysctl("hw.logicalcpu")
        physical = int(physical_raw) if physical_raw and physical_raw.isdigit() else None
        logical = int(logical_raw) if logical_raw and logical_raw.isdigit() else (os.cpu_count() or 1)
        version = platform.mac_ver()[0] or "unknown"
        return PlatformInfo(
            os_name="macOS",
            distribution="macOS",
            distribution_version=version,
            kernel=platform.release() or "unknown",
            architecture=arch,
            cpu_model=(cpu_model or platform.processor() or "unknown")[:256],
            logical_cpus=logical,
            physical_cores=physical,
            platform_family=self.family,
            model=self._sysctl("hw.model"),
            apple_silicon=apple_silicon,
        )

    def capabilities(self) -> dict[str, Capability]:
        # Apple does not expose a stable public userspace temperature ABI that
        # ShopOS can rely on without private frameworks or privileged tools.
        return {
            "temperature": Capability("unavailable", "Keine stabile öffentliche Apple-Sensor-API im Basismodul."),
            "undervoltage": Capability("unsupported", "Kein Raspberry-Pi-Undervoltage-Modell."),
            "gpio": Capability("unsupported", "Nicht Teil der macOS-Hardwareplattform."),
            "i2c": Capability("unsupported", "Nicht als allgemeine macOS-Benutzerschnittstelle verfügbar."),
            "spi": Capability("unsupported", "Nicht als allgemeine macOS-Benutzerschnittstelle verfügbar."),
        }
