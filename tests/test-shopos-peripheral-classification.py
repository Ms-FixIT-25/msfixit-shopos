from __future__ import annotations

import tempfile
from pathlib import Path

from hardware_manager.peripherals import classify_usb


def write(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


with tempfile.TemporaryDirectory() as raw:
    root = Path(raw)
    device = root / "1-1"
    device.mkdir()

    keyboard_input = root / "1-1:1.0" / "input" / "input7"
    write(keyboard_input / "name", "Generic USB Keyboard")
    write(keyboard_input / "capabilities" / "key", "1")
    result = classify_usb(device, "Generic", "USB Keyboard")
    assert result.kind == "keyboard"
    assert "hid-keyboard" in result.capabilities

with tempfile.TemporaryDirectory() as raw:
    root = Path(raw)
    device = root / "2-1"
    device.mkdir()
    scanner_input = root / "2-1:1.0" / "input" / "input8"
    write(scanner_input / "name", "Barcode Scanner")
    write(scanner_input / "capabilities" / "key", "1")
    result = classify_usb(device, "Honeywell", "Barcode Scanner")
    assert result.kind == "barcode_scanner"
    assert "barcode-input" in result.capabilities

with tempfile.TemporaryDirectory() as raw:
    root = Path(raw)
    device = root / "3-1"
    device.mkdir()
    mouse_input = root / "3-1:1.0" / "input" / "input9"
    write(mouse_input / "name", "USB Mouse")
    write(mouse_input / "capabilities" / "rel", "3")
    result = classify_usb(device, "Generic", "Mouse")
    assert result.kind == "mouse"

with tempfile.TemporaryDirectory() as raw:
    root = Path(raw)
    device = root / "4-1"
    device.mkdir()
    result = classify_usb(device, "Zebra", "Label Printer")
    assert result.kind == "label_printer"

with tempfile.TemporaryDirectory() as raw:
    root = Path(raw)
    device = root / "5-1"
    device.mkdir()
    result = classify_usb(device, "Unknown", "Mystery Gadget")
    assert result.kind == "unknown"

print("PASS: semantic peripheral classification covers keyboard, mouse, barcode scanner, printer and unknown devices.")
