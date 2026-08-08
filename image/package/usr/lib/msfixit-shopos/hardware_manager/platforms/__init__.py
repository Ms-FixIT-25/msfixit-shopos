from __future__ import annotations

import platform

from .base import PlatformAdapter
from .linux import LinuxAdapter
from .macos import MacOSAdapter
from .raspberry_pi import RaspberryPiAdapter


def select_adapter() -> PlatformAdapter:
    system = platform.system().lower()
    if system == "darwin":
        return MacOSAdapter()
    if system == "linux":
        if RaspberryPiAdapter.is_raspberry_pi():
            return RaspberryPiAdapter()
        return LinuxAdapter()
    return PlatformAdapter()


__all__ = ["PlatformAdapter", "LinuxAdapter", "RaspberryPiAdapter", "MacOSAdapter", "select_adapter"]
