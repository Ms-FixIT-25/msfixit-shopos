from __future__ import annotations

from pathlib import Path

from hardware_manager.models import Capability, PlatformInfo
from .base import read_text
from .linux import LinuxAdapter


class RaspberryPiAdapter(LinuxAdapter):
    family = "raspberry-pi"

    @staticmethod
    def is_raspberry_pi() -> bool:
        model = (read_text("/proc/device-tree/model") or "").lower()
        if "raspberry pi" in model:
            return True
        cpuinfo = (read_text("/proc/cpuinfo") or "").lower()
        return "raspberry pi" in cpuinfo or "bcm2711" in cpuinfo or "bcm2712" in cpuinfo

    @staticmethod
    def _revision() -> str | None:
        text = read_text("/proc/cpuinfo") or ""
        for line in text.splitlines():
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            if key.strip() == "Revision":
                revision = value.strip().lower()
                if revision and all(ch in "0123456789abcdef" for ch in revision) and len(revision) <= 16:
                    return revision
        return None

    def platform_info(self) -> PlatformInfo:
        info = super().platform_info()
        model = read_text("/proc/device-tree/model")
        return PlatformInfo(
            os_name=info.os_name,
            distribution=info.distribution,
            distribution_version=info.distribution_version,
            kernel=info.kernel,
            architecture=info.architecture,
            cpu_model=info.cpu_model,
            logical_cpus=info.logical_cpus,
            physical_cores=info.physical_cores,
            platform_family=self.family,
            model=(model or "Raspberry Pi")[:256],
            board_revision=self._revision(),
            virtualization=info.virtualization,
        )

    def capabilities(self) -> dict[str, Capability]:
        caps = super().capabilities()
        caps["undervoltage"] = Capability("available", "Raspberry-Pi-Firmwarestatus über vcgencmd, falls installiert.")
        caps["gpio"] = Capability(
            "available" if Path("/dev/gpiomem").exists() or Path("/sys/class/gpio").exists() else "unavailable",
            "GPIO-Geräteschnittstelle erkannt." if Path("/dev/gpiomem").exists() else "",
        )
        caps["i2c"] = Capability(
            "available" if any(Path("/dev").glob("i2c-*")) else "unavailable",
            "Aktives I²C-Gerät erkannt." if any(Path("/dev").glob("i2c-*")) else "I²C ist möglicherweise deaktiviert.",
        )
        caps["spi"] = Capability(
            "available" if any(Path("/dev").glob("spidev*")) else "unavailable",
            "Aktives SPI-Gerät erkannt." if any(Path("/dev").glob("spidev*")) else "SPI ist möglicherweise deaktiviert.",
        )
        return caps
