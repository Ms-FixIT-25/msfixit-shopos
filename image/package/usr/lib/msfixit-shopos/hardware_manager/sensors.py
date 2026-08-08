from __future__ import annotations

import math
import os
import re
import shutil
from pathlib import Path

from hardware_manager.models import (
    CpuSnapshot,
    MemorySnapshot,
    NetworkInterface,
    PrinterDevice,
    ServiceSnapshot,
    StorageSnapshot,
    ThermalSensor,
    UsbDevice,
)
from hardware_manager.peripherals import classify_usb
from hardware_manager.platforms.base import read_text, run_command

_NUMERIC_RE = re.compile(r"^-?[0-9]+(?:\.[0-9]+)?$")
_UNIT_RE = re.compile(r"^[A-Za-z0-9_.@:-]{1,96}\.service$")
_THROTTLED_RE = re.compile(r"^throttled=0x([0-9a-fA-F]+)$")
_PRINTER_RE = re.compile(r"^printer ([A-Za-z0-9_.-]{1,127}) is (.+)$")


def _safe_int(value: str | None) -> int | None:
    if value is None:
        return None
    value = value.strip()
    if not value.isdigit():
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _safe_float(value: str | None) -> float | None:
    if value is None or not _NUMERIC_RE.fullmatch(value.strip()):
        return None
    try:
        number = float(value)
    except ValueError:
        return None
    return number if math.isfinite(number) else None


def _bytes_from_kib(value: str | None) -> int | None:
    parsed = _safe_int(value)
    return parsed * 1024 if parsed is not None else None


class SensorCollector:
    def __init__(self, platform_family: str) -> None:
        self.platform_family = platform_family
        self._previous_cpu: tuple[int, ...] | None = None

    def memory(self) -> MemorySnapshot:
        values: dict[str, str] = {}
        text = read_text("/proc/meminfo") or ""
        for line in text.splitlines():
            if ":" not in line:
                continue
            key, rest = line.split(":", 1)
            parts = rest.strip().split()
            if parts:
                values[key] = parts[0]
        return MemorySnapshot(
            total_bytes=_bytes_from_kib(values.get("MemTotal")),
            available_bytes=_bytes_from_kib(values.get("MemAvailable")),
            swap_total_bytes=_bytes_from_kib(values.get("SwapTotal")),
            swap_free_bytes=_bytes_from_kib(values.get("SwapFree")),
        )

    @staticmethod
    def _cpu_ticks() -> tuple[int, ...] | None:
        text = read_text("/proc/stat", max_bytes=128 * 1024) or ""
        first = text.splitlines()[0] if text else ""
        fields = first.split()
        if not fields or fields[0] != "cpu":
            return None
        ticks: list[int] = []
        for value in fields[1:11]:
            if not value.isdigit():
                return None
            ticks.append(int(value))
        return tuple(ticks)

    @staticmethod
    def _frequency_mhz() -> float | None:
        values: list[float] = []
        for policy in sorted(Path("/sys/devices/system/cpu/cpufreq").glob("policy*")):
            raw = _safe_float(read_text(policy / "scaling_cur_freq"))
            if raw is not None and 10_000 <= raw <= 10_000_000:
                values.append(raw / 1000.0)
        return round(sum(values) / len(values), 1) if values else None

    @staticmethod
    def _governors() -> tuple[str | None, list[str]]:
        active: list[str] = []
        available: set[str] = set()
        for policy in sorted(Path("/sys/devices/system/cpu/cpufreq").glob("policy*")):
            governor = read_text(policy / "scaling_governor")
            if governor and re.fullmatch(r"[a-zA-Z0-9_-]{1,32}", governor):
                active.append(governor)
            for item in (read_text(policy / "scaling_available_governors") or "").split():
                if re.fullmatch(r"[a-zA-Z0-9_-]{1,32}", item):
                    available.add(item)
        selected = active[0] if active and len(set(active)) == 1 else ("mixed" if active else None)
        return selected, sorted(available)

    def cpu(self) -> CpuSnapshot:
        current = self._cpu_ticks()
        utilization = None
        iowait = None
        if current is not None and self._previous_cpu is not None and len(current) == len(self._previous_cpu):
            delta = tuple(max(0, now - before) for now, before in zip(current, self._previous_cpu))
            total = sum(delta)
            if total > 0:
                idle = delta[3] + (delta[4] if len(delta) > 4 else 0)
                utilization = round(max(0.0, min(100.0, (total - idle) * 100.0 / total)), 1)
                if len(delta) > 4:
                    iowait = round(max(0.0, min(100.0, delta[4] * 100.0 / total)), 1)
        self._previous_cpu = current
        try:
            load = os.getloadavg()
        except (OSError, AttributeError):
            load = (None, None, None)
        governor, available = self._governors()
        return CpuSnapshot(
            utilization_percent=utilization,
            iowait_percent=iowait,
            load_1m=round(float(load[0]), 2) if load[0] is not None else None,
            load_5m=round(float(load[1]), 2) if load[1] is not None else None,
            load_15m=round(float(load[2]), 2) if load[2] is not None else None,
            frequency_mhz=self._frequency_mhz(),
            governor=governor,
            available_governors=available,
        )

    @staticmethod
    def thermal_sensors() -> list[ThermalSensor]:
        sensors: list[ThermalSensor] = []
        seen: set[str] = set()
        for zone in sorted(Path("/sys/class/thermal").glob("thermal_zone*")):
            raw = _safe_float(read_text(zone / "temp"))
            if raw is None:
                continue
            temperature = raw / 1000.0 if abs(raw) > 500 else raw
            if not -20.0 <= temperature <= 130.0:
                continue
            source = str(zone / "temp")
            label = (read_text(zone / "type") or zone.name)[:96]
            sensors.append(ThermalSensor(source=source, label=label, temperature_c=round(temperature, 1)))
            seen.add(source)
        for hwmon in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
            chip = (read_text(hwmon / "name") or hwmon.name)[:64]
            for input_file in sorted(hwmon.glob("temp[0-9]*_input")):
                source = str(input_file.resolve())
                if source in seen:
                    continue
                raw = _safe_float(read_text(input_file))
                if raw is None:
                    continue
                temperature = raw / 1000.0 if abs(raw) > 500 else raw
                if not -20.0 <= temperature <= 130.0:
                    continue
                stem = input_file.name.removesuffix("_input")
                label = read_text(hwmon / f"{stem}_label") or f"{chip}:{stem}"
                sensors.append(ThermalSensor(source=str(input_file), label=label[:96], temperature_c=round(temperature, 1)))
                seen.add(source)
        return sensors

    def raspberry_pi_throttled(self) -> int | None:
        if self.platform_family != "raspberry-pi":
            return None
        for candidate in ("/usr/bin/vcgencmd", "/opt/vc/bin/vcgencmd"):
            if Path(candidate).is_file():
                output = run_command([candidate, "get_throttled"], timeout=2.0)
                match = _THROTTLED_RE.fullmatch(output or "")
                if match:
                    try:
                        return int(match.group(1), 16)
                    except ValueError:
                        return None
        return None

    @staticmethod
    def _mount_record(mountpoint: str) -> tuple[str | None, str | None]:
        text = read_text("/proc/mounts", max_bytes=512 * 1024) or ""
        fallback: tuple[str | None, str | None] = (None, None)
        for line in text.splitlines():
            fields = line.split()
            if len(fields) < 3:
                continue
            source, mounted, filesystem = fields[:3]
            if mounted == mountpoint:
                return source, filesystem
            if mounted == "/" and fallback == (None, None):
                fallback = (source, filesystem)
        return fallback

    @staticmethod
    def _base_block_device(source: str | None) -> str | None:
        if not source or not source.startswith("/dev/"):
            return None
        name = Path(source).name
        for pattern in (r"^(mmcblk\d+)p\d+$", r"^(nvme\d+n\d+)p\d+$", r"^([a-zA-Z]+)\d+$"):
            match = re.fullmatch(pattern, name)
            if match:
                return match.group(1)
        return name if re.fullmatch(r"[A-Za-z0-9._-]+", name) else None

    @staticmethod
    def _boot_medium(source: str | None) -> str:
        if not source:
            return "unknown"
        name = Path(source).name.lower()
        if name.startswith("mmcblk"):
            return "sd/emmc"
        if name.startswith("nvme"):
            return "nvme"
        if name.startswith("sd"):
            return "usb/scsi"
        if name.startswith(("vd", "xvd")):
            return "virtual"
        return "other"

    def storage(self) -> StorageSnapshot:
        mountpoint = "/data" if Path("/data").is_dir() else "/"
        source, filesystem = self._mount_record(mountpoint)
        try:
            usage = shutil.disk_usage(mountpoint)
            total_bytes, free_bytes = int(usage.total), int(usage.free)
        except OSError:
            total_bytes = free_bytes = None
        base = self._base_block_device(source)
        trim = None
        if base:
            discard = _safe_int(read_text(Path("/sys/class/block") / base / "queue/discard_max_bytes"))
            trim = discard > 0 if discard is not None else None
        return StorageSnapshot(mountpoint, source, filesystem, total_bytes, free_bytes, self._boot_medium(source), trim)

    @staticmethod
    def _wireless_signals() -> dict[str, float]:
        result: dict[str, float] = {}
        text = read_text("/proc/net/wireless") or ""
        for line in text.splitlines()[2:]:
            if ":" not in line:
                continue
            name, rest = line.split(":", 1)
            fields = rest.split()
            signal = _safe_float(fields[2].rstrip(".")) if len(fields) >= 3 else None
            if signal is not None and -150 <= signal <= 0:
                result[name.strip()] = signal
        return result

    def network(self) -> list[NetworkInterface]:
        counters: dict[str, tuple[int | None, int | None, int | None, int | None]] = {}
        text = read_text("/proc/net/dev") or ""
        for line in text.splitlines()[2:]:
            if ":" not in line:
                continue
            name, raw = line.split(":", 1)
            name = name.strip()
            fields = raw.split()
            if len(fields) < 16 or not re.fullmatch(r"[A-Za-z0-9_.:-]{1,64}", name):
                continue
            counters[name] = (_safe_int(fields[0]), _safe_int(fields[8]), _safe_int(fields[2]), _safe_int(fields[10]))
        wireless_signals = self._wireless_signals()
        interfaces: list[NetworkInterface] = []
        for name in sorted(counters):
            if name == "lo":
                continue
            base = Path("/sys/class/net") / name
            state = (read_text(base / "operstate") or "unknown")[:32]
            speed = _safe_int(read_text(base / "speed"))
            if speed is not None and not 1 <= speed <= 1_000_000:
                speed = None
            mtu = _safe_int(read_text(base / "mtu"))
            if mtu is not None and not 68 <= mtu <= 1_000_000:
                mtu = None
            duplex_raw = (read_text(base / "duplex") or "").lower()
            duplex = duplex_raw if duplex_raw in {"full", "half", "unknown"} else None
            wireless = name in wireless_signals or (base / "wireless").exists()
            rx, tx, rx_errors, tx_errors = counters[name]
            interfaces.append(NetworkInterface(
                name=name,
                state=state,
                rx_bytes=rx,
                tx_bytes=tx,
                rx_errors=rx_errors,
                tx_errors=tx_errors,
                speed_mbps=speed,
                wireless_signal_dbm=wireless_signals.get(name),
                duplex=duplex,
                mtu=mtu,
                wireless=wireless,
            ))
        return interfaces

    @staticmethod
    def usb() -> list[UsbDevice]:
        devices: list[UsbDevice] = []
        for entry in sorted(Path("/sys/bus/usb/devices").glob("*")):
            vendor = read_text(entry / "idVendor")
            product_id = read_text(entry / "idProduct")
            if not vendor or not product_id or not re.fullmatch(r"[0-9a-fA-F]{4}", vendor) or not re.fullmatch(r"[0-9a-fA-F]{4}", product_id):
                continue
            speed = _safe_float(read_text(entry / "speed"))
            if speed is not None and not 0 < speed <= 80_000:
                speed = None
            usb_spec = read_text(entry / "bcdUSB")
            if usb_spec and not re.fullmatch(r"[0-9.]{3,8}", usb_spec):
                usb_spec = None
            manufacturer = (read_text(entry / "manufacturer") or "")[:128] or None
            product = (read_text(entry / "product") or "")[:128] or None
            classification = classify_usb(entry, manufacturer, product)
            devices.append(UsbDevice(
                sysfs_name=entry.name[:64],
                vendor_id=vendor.lower(),
                product_id=product_id.lower(),
                manufacturer=manufacturer,
                product=product,
                usb_spec=usb_spec,
                negotiated_mbps=round(speed, 1) if speed is not None else None,
                kind=classification.kind,
                capabilities=list(classification.capabilities),
            ))
        return devices

    @staticmethod
    def printers() -> list[PrinterDevice]:
        if not Path("/usr/bin/lpstat").exists():
            return []
        output = run_command(["/usr/bin/lpstat", "-p"], timeout=3.0) or ""
        result: list[PrinterDevice] = []
        for line in output.splitlines()[:100]:
            match = _PRINTER_RE.match(line.strip())
            if not match:
                continue
            detail = match.group(2).lower()
            if "disabled" in detail:
                state = "disabled"
            elif "printing" in detail:
                state = "printing"
            else:
                state = "idle"
            result.append(PrinterDevice(name=match.group(1), state=state))
        return result

    @staticmethod
    def _shopos_units() -> list[str]:
        units: set[str] = {"nginx.service", "mariadb.service", "redis-server.service"}
        for root in (Path("/etc/systemd/system"), Path("/lib/systemd/system"), Path("/usr/lib/systemd/system")):
            if not root.is_dir():
                continue
            for path in root.glob("msfixit-*.service"):
                if _UNIT_RE.fullmatch(path.name):
                    units.add(path.name)
            for path in root.glob("php*-fpm.service"):
                if _UNIT_RE.fullmatch(path.name):
                    units.add(path.name)
        return sorted(units)

    @staticmethod
    def services() -> list[ServiceSnapshot]:
        if not Path("/usr/bin/systemctl").exists():
            return []
        result: list[ServiceSnapshot] = []
        for unit in SensorCollector._shopos_units():
            output = run_command([
                "/usr/bin/systemctl",
                "show",
                unit,
                "--property=ActiveState,MemoryCurrent,CPUUsageNSec",
                "--value",
            ], timeout=2.0)
            if output is None:
                continue
            values = output.splitlines()
            if not values:
                continue
            state = values[0][:32] if values else "unknown"
            memory_bytes = _safe_int(values[1]) if len(values) > 1 else None
            cpu_usage_nsec = _safe_int(values[2]) if len(values) > 2 else None
            result.append(ServiceSnapshot(unit, state, memory_bytes, cpu_usage_nsec))
        return result
