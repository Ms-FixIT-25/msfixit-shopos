from __future__ import annotations

import os
import platform
import subprocess
from pathlib import Path

from hardware_manager.models import Capability, PlatformInfo

MAX_TEXT_BYTES = 256 * 1024


def read_text(path: str | Path, *, max_bytes: int = MAX_TEXT_BYTES) -> str | None:
    try:
        with open(path, "rb") as handle:
            data = handle.read(max_bytes + 1)
        if len(data) > max_bytes:
            return None
        return data.decode("utf-8", errors="replace").replace("\x00", "").strip()
    except (OSError, ValueError):
        return None


def run_command(args: list[str], *, timeout: float = 2.0) -> str | None:
    if not args or any(not isinstance(value, str) or "\x00" in value for value in args):
        return None
    try:
        result = subprocess.run(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
            env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL": "C"},
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    output = result.stdout.strip()
    if len(output.encode("utf-8", errors="ignore")) > MAX_TEXT_BYTES:
        return None
    return output


class PlatformAdapter:
    family = "unsupported"

    def platform_info(self) -> PlatformInfo:
        logical = os.cpu_count() or 1
        return PlatformInfo(
            os_name=platform.system() or "unknown",
            distribution="unknown",
            distribution_version="unknown",
            kernel=platform.release() or "unknown",
            architecture=platform.machine() or "unknown",
            cpu_model=platform.processor() or "unknown",
            logical_cpus=logical,
            physical_cores=None,
            platform_family=self.family,
            virtualization=None,
        )

    def capabilities(self) -> dict[str, Capability]:
        return {
            "temperature": Capability("unsupported", "Platformadapter nicht implementiert."),
            "undervoltage": Capability("unsupported", "Nur auf unterstützter Hardware verfügbar."),
            "gpio": Capability("unsupported", "Nur auf unterstützter Hardware verfügbar."),
            "i2c": Capability("unsupported", "Nur auf unterstützter Hardware verfügbar."),
            "spi": Capability("unsupported", "Nur auf unterstützter Hardware verfügbar."),
            "printers": Capability("unsupported", "Plattformadapter nicht implementiert."),
        }
