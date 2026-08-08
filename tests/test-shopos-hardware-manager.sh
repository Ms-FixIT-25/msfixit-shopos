#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/image/package/usr/lib/msfixit-shopos"
manager="$lib/hardware_manager/manager.py"
sensors="$lib/hardware_manager/sensors.py"
rules="$lib/hardware_manager/rules.py"
thermal="$lib/hardware_manager/thermal.py"
state="$lib/hardware_manager/state.py"
actions="$lib/hardware_manager/actions.py"
service="$root/image/package/etc/systemd/system/msfixit-hardware-manager.service"
sudoers="$root/image/package/etc/sudoers.d/msfixit-shopos-hardware-manager"
postinst="$root/image/package/DEBIAN/postinst"
nginx="$root/image/package/etc/nginx/snippets/msfixit-admin-console.conf"
gui="$root/image/package/usr/share/msfixit-shopos/admin-console/public/hardware.php"
helper="$root/image/package/usr/local/sbin/msfixit-hardware-action"
runner="$root/image/package/usr/local/sbin/msfixit-hardware-manager"

mapfile -t modules < <(find "$lib/hardware_manager" -type f -name '*.py' | sort)
python3 -m py_compile "${modules[@]}" "$helper" "$runner"
php -l "$gui" >/dev/null

PYTHONPATH="$lib" python3 - <<'PY'
from hardware_manager.models import CpuSnapshot, MemorySnapshot, StorageSnapshot, ThermalSnapshot
from hardware_manager.rules import RuleEngine
from hardware_manager.state import Settings
from hardware_manager.thermal import ThermalPolicy, ThermalStateMachine

policy = ThermalPolicy.for_platform('raspberry-pi', 'Raspberry Pi 4 Model B')
assert (policy.elevated_c, policy.warning_c, policy.critical_c, policy.emergency_c) == (60.0, 70.0, 78.0, 83.0)
assert policy.shutdown_enabled is False
machine = ThermalStateMachine(policy)
for i in range(3):
    decision = machine.update(72.0, now=float(i))
assert decision.level == 'warning'
for i in range(3, 6):
    decision = machine.update(80.0, now=float(i))
assert decision.level == 'critical'
for i in range(6, 10):
    decision = machine.update(85.0, now=float(i))
assert decision.level == 'emergency'
assert decision.shutdown_eligible is False

armed = ThermalPolicy(60.0, 70.0, 78.0, 83.0, shutdown_enabled=True, emergency_min_seconds=120)
armed_machine = ThermalStateMachine(armed)
for i in range(4):
    decision = armed_machine.update(85.0, now=float(i))
assert decision.level == 'emergency'
assert decision.shutdown_eligible is False
decision = armed_machine.update(85.0, now=124.0)
assert decision.shutdown_eligible is True

settings = Settings.from_dict({'sample_interval_seconds': 1, 'persist_interval_seconds': 1, 'history_samples': 99999})
assert settings.sample_interval_seconds == 10
assert settings.persist_interval_seconds == 60
assert settings.history_samples == 720
assert settings.mode == 'observe'
assert settings.emergency_shutdown_enabled is False

cpu = CpuSnapshot(10.0, 0.0, 0.1, 0.1, 0.1, 1500.0, 'performance', ['performance', 'schedutil', 'powersave'])
mem = MemorySnapshot(8_000_000_000, 6_000_000_000, 0, 0)
thermal = ThermalSnapshot([], 45.0, 'normal')
storage = StorageSnapshot('/data', '/dev/sda2', 'ext4', 100_000_000, 80_000_000, 'usb/scsi', True)
engine = RuleEngine()
pi = engine.evaluate(platform_family='raspberry-pi', cpu=cpu, memory=mem, thermal=thermal, storage=storage, network=[], usb=[], services=[])
linux = engine.evaluate(platform_family='linux', cpu=cpu, memory=mem, thermal=thermal, storage=storage, network=[], usb=[], services=[])
assert any(r.action_id == 'set-governor' and r.action_value == 'schedutil' for r in pi)
assert not any(r.action_id == 'set-governor' for r in linux)
PY

grep -Fq 'User=shopos-hwmon' "$service"
grep -Fq 'SupplementaryGroups=shopos-hwapi' "$service"
grep -Fq 'CPUQuota=20%' "$service"
grep -Fq 'MemoryMax=96M' "$service"
grep -Fq 'IOSchedulingClass=idle' "$service"
grep -Fq 'ProtectSystem=strict' "$service"
grep -Fq 'ProtectKernelModules=true' "$service"
grep -Fq 'ProtectKernelLogs=true' "$service"
grep -Fq 'RestrictAddressFamilies=AF_UNIX' "$service"
# The manager deliberately uses one sudo allowlisted helper for reversible
# cpufreq writes. These systemd directives would make that helper impossible.
if grep -Eq '^NoNewPrivileges=(yes|true)$' "$service"; then
    echo 'NoNewPrivileges would block the allowlisted Hardware Manager sudo helper.' >&2
    exit 1
fi
if grep -Eq '^ProtectKernelTunables=(yes|true)$' "$service"; then
    echo 'ProtectKernelTunables would make the validated cpufreq sysfs write read-only.' >&2
    exit 1
fi

grep -Fq 'shopos-hwmon ALL=(root) NOPASSWD: /usr/local/sbin/msfixit-hardware-action *' "$sudoers"
if grep -Fq 'NOPASSWD: ALL' "$sudoers"; then echo 'Hardware Manager sudoers must never grant unrestricted root.' >&2; exit 1; fi
if grep -Fq 'www-data ALL=' "$sudoers"; then echo 'Web server must not call Hardware Manager root helper directly.' >&2; exit 1; fi

grep -Fq 'groupadd --system shopos-hwapi' "$postinst"
grep -Fq 'usermod -a -G shopos-hwapi shopos-hwmon' "$postinst"
grep -Fq 'usermod -a -G shopos-hwapi www-data' "$postinst"
grep -Fq 'systemctl enable msfixit-hardware-manager.service' "$postinst"
grep -Fq 'location = /admin/hardware {' "$nginx"
grep -Fq "session_name('SHOPOSADMIN')" "$gui"
grep -Fq "hash_equals(csrf()" "$gui"
grep -Fq 'unix:///run/msfixit-hardware-manager/api.sock' "$gui"
grep -Fq "name=\"password\"" "$gui"

grep -Fq 'duplex=duplex' "$sensors"
grep -Fq 'mtu=mtu' "$sensors"
grep -Fq 'def printers' "$sensors"
if grep -Eq '(ip address|ip -j|ifconfig|address$|MAC|mac_address)' "$sensors"; then
    echo 'Hardware Manager must not collect IP/MAC identity data.' >&2
    exit 1
fi

# Detect executable shutdown paths, not harmless documentation/log strings that
# explain that shutdown remains blocked. The self-test prevents this guard from
# regressing back to a plain-text keyword search.
python3 - "$manager" "$helper" <<'PY'
import ast
import pathlib
import sys

PROCESS_CALLS = {
    'os.system',
    'subprocess.call',
    'subprocess.check_call',
    'subprocess.check_output',
    'subprocess.Popen',
    'subprocess.run',
}
DANGEROUS = {'halt', 'poweroff', 'reboot', 'shutdown'}


def dotted_name(node: ast.AST) -> str:
    parts: list[str] = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return '.'.join(reversed(parts))


def literal_command(node: ast.AST) -> list[str] | None:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value.split()
    if isinstance(node, (ast.List, ast.Tuple)):
        result: list[str] = []
        for item in node.elts:
            if not isinstance(item, ast.Constant) or not isinstance(item.value, str):
                return None
            result.append(item.value)
        return result
    return None


def contains_power_action(tokens: list[str]) -> bool:
    normalized = [pathlib.PurePath(token).name.lower() for token in tokens]
    if any(token in DANGEROUS for token in normalized):
        return True
    return 'systemctl' in normalized and any(token in DANGEROUS for token in normalized)


def scan(source: str, label: str) -> list[str]:
    tree = ast.parse(source, filename=label)
    findings: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not node.args:
            continue
        if dotted_name(node.func) not in PROCESS_CALLS:
            continue
        command = literal_command(node.args[0])
        if command is not None and contains_power_action(command):
            findings.append(f'{label}:{getattr(node, "lineno", "?")}: {command!r}')
    return findings

# Regression proof: plain log text is safe, but an actual subprocess poweroff
# must be rejected by this scanner.
assert scan("print('automatic poweroff intentionally blocked pending real-hardware validation')\n", 'safe-log.py') == []
assert scan("import subprocess\nsubprocess.run(['/usr/bin/systemctl','poweroff'])\n", 'unsafe-call.py')

findings: list[str] = []
for raw in sys.argv[1:]:
    path = pathlib.Path(raw)
    findings.extend(scan(path.read_text(encoding='utf-8'), str(path)))
if findings:
    print('Automatic emergency poweroff must remain blocked until physical hardware validation.', file=sys.stderr)
    for finding in findings:
        print(f'  {finding}', file=sys.stderr)
    raise SystemExit(1)
PY

# Overclock/voltage tuning can only become effective through the privileged
# Hardware Manager helper. Keep the root helper free of those tunables while
# allowing user-facing recommendation text to state that overclocking is
# explicitly excluded. The action layer must remain restricted to governors.
if grep -Eqi '(over_voltage|arm_freq|core_freq|force_turbo|overclock)' "$helper"; then
    echo 'Hardware Manager privileged helper must not implement overclock/voltage tuning.' >&2
    exit 1
fi
grep -Fq 'allowed = {"set-governor": {"schedutil", "powersave"}}' "$actions"
grep -Fq 'Aggressives Overclocking ist ausgeschlossen.' "$rules"

grep -Fq 'automatic poweroff intentionally blocked pending real-hardware validation' "$manager"
printf 'PASS: Hardware Manager is platform-aware, bounded, reversible and fail-safe before physical shutdown validation.\n'
