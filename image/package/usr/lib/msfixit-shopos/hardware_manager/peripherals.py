from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from hardware_manager.platforms.base import read_text


@dataclass(frozen=True, slots=True)
class PeripheralClassification:
    kind: str
    capabilities: tuple[str, ...]


def _has_hid_usage(entry: Path, usage: str) -> bool:
    for interface in entry.parent.glob(f"{entry.name}:*"):
        for input_dir in interface.glob("input/input*"):
            capabilities = read_text(input_dir / "capabilities/key") or ""
            name = (read_text(input_dir / "name") or "").lower()
            if usage == "keyboard" and capabilities.strip("0 "):
                if "keyboard" in name or "scanner" in name or "barcode" in name:
                    return True
            if usage == "mouse":
                rel = read_text(input_dir / "capabilities/rel") or ""
                if rel.strip("0 ") or "mouse" in name:
                    return True
            if usage == "touchscreen":
                abs_caps = read_text(input_dir / "capabilities/abs") or ""
                if abs_caps.strip("0 ") and ("touch" in name or "screen" in name):
                    return True
    return False


def classify_usb(entry: Path, manufacturer: str | None, product: str | None) -> PeripheralClassification:
    text = " ".join(part for part in ((manufacturer or ""), (product or "")) if part).lower()
    caps: list[str] = []

    if _has_hid_usage(entry, "mouse"):
        return PeripheralClassification("mouse", ("pointer", "hotplug"))
    if _has_hid_usage(entry, "touchscreen"):
        return PeripheralClassification("touchscreen", ("absolute-pointer", "hotplug"))
    if _has_hid_usage(entry, "keyboard"):
        if any(token in text for token in ("barcode", "scanner", "scan gun", "handscanner")):
            return PeripheralClassification("barcode_scanner", ("hid-keyboard", "barcode-input", "hotplug"))
        return PeripheralClassification("keyboard", ("hid-keyboard", "hotplug"))

    if any(token in text for token in ("barcode", "scanner", "scan gun", "handscanner")):
        return PeripheralClassification("barcode_scanner", ("barcode-input", "hotplug"))
    if any(token in text for token in ("label", "zebra")) and "printer" in text:
        return PeripheralClassification("label_printer", ("print", "hotplug"))
    if any(token in text for token in ("receipt", "thermal", "epson tm", "star micronics")):
        return PeripheralClassification("receipt_printer", ("print", "hotplug"))
    if "printer" in text:
        return PeripheralClassification("a4_printer", ("print", "hotplug"))
    if any(token in text for token in ("storage", "flash", "ssd", "hard drive", "mass storage")):
        return PeripheralClassification("storage", ("block-storage", "hotplug"))
    if any(token in text for token in ("serial", "uart", "ft232", "cp210", "ch340")):
        return PeripheralClassification("serial_adapter", ("serial", "hotplug"))

    return PeripheralClassification("unknown", tuple(caps))
