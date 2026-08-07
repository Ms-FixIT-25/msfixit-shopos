from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Literal

Availability = Literal["available", "unavailable", "unsupported", "error"]
ThermalLevel = Literal["normal", "elevated", "warning", "critical", "emergency"]
OperatingMode = Literal["observe", "recommend", "automatic"]


@dataclass(slots=True)
class Capability:
    state: Availability
    reason: str = ""


@dataclass(slots=True)
class PlatformInfo:
    os_name: str
    distribution: str
    distribution_version: str
    kernel: str
    architecture: str
    cpu_model: str
    logical_cpus: int
    physical_cores: int | None
    platform_family: str
    model: str | None = None
    board_revision: str | None = None
    apple_silicon: bool | None = None


@dataclass(slots=True)
class MemorySnapshot:
    total_bytes: int | None
    available_bytes: int | None
    swap_total_bytes: int | None
    swap_free_bytes: int | None


@dataclass(slots=True)
class CpuSnapshot:
    utilization_percent: float | None
    iowait_percent: float | None
    load_1m: float | None
    load_5m: float | None
    load_15m: float | None
    frequency_mhz: float | None
    governor: str | None
    available_governors: list[str] = field(default_factory=list)


@dataclass(slots=True)
class ThermalSensor:
    source: str
    label: str
    temperature_c: float


@dataclass(slots=True)
class ThermalSnapshot:
    sensors: list[ThermalSensor]
    primary_c: float | None
    level: ThermalLevel
    current_throttling: bool | None = None
    throttling_occurred: bool | None = None
    current_undervoltage: bool | None = None
    undervoltage_occurred: bool | None = None
    raw_throttled_mask: int | None = None
    emergency_seconds: int = 0
    shutdown_eligible: bool = False
    decision_reason: str = ""


@dataclass(slots=True)
class StorageSnapshot:
    mountpoint: str
    source: str | None
    filesystem: str | None
    total_bytes: int | None
    free_bytes: int | None
    boot_medium: str
    trim_supported: bool | None


@dataclass(slots=True)
class NetworkInterface:
    name: str
    state: str
    rx_bytes: int | None
    tx_bytes: int | None
    rx_errors: int | None
    tx_errors: int | None
    speed_mbps: int | None
    wireless_signal_dbm: float | None


@dataclass(slots=True)
class UsbDevice:
    sysfs_name: str
    vendor_id: str | None
    product_id: str | None
    manufacturer: str | None
    product: str | None
    usb_spec: str | None
    negotiated_mbps: float | None


@dataclass(slots=True)
class ServiceSnapshot:
    unit: str
    active_state: str
    memory_bytes: int | None
    cpu_usage_nsec: int | None


@dataclass(slots=True)
class Recommendation:
    id: str
    severity: Literal["info", "notice", "warning", "critical"]
    title: str
    problem: str
    cause: str
    impact: str
    action: str
    expected_benefit: str
    risk: str
    permission: str
    reversible: bool
    automatable: bool
    action_id: str | None = None
    action_value: str | None = None


@dataclass(slots=True)
class Snapshot:
    timestamp: str
    platform: PlatformInfo
    cpu: CpuSnapshot
    memory: MemorySnapshot
    thermal: ThermalSnapshot
    storage: StorageSnapshot
    network: list[NetworkInterface]
    usb: list[UsbDevice]
    services: list[ServiceSnapshot]
    recommendations: list[Recommendation]
    capabilities: dict[str, Capability]
    mode: OperatingMode

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)
