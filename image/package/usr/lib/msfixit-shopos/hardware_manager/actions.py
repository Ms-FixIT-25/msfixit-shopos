from __future__ import annotations

import json
import re
import subprocess
from typing import Any

_TXN_RE = re.compile(r"^[a-f0-9]{24}$")


def verify_admin_password(password: str) -> bool:
    if not password or len(password) > 4096 or "\x00" in password:
        return False
    php = r'''
$config = is_file('/etc/msfixit-shopos/admin-console.php')
    ? require '/etc/msfixit-shopos/admin-console.php' : [];
$hash = is_array($config) ? (string)($config['password_hash'] ?? '') : '';
$password = stream_get_contents(STDIN);
if ($password !== false) { $password = rtrim($password, "\r\n"); }
exit($hash !== '' && is_string($password) && password_verify($password, $hash) ? 0 : 1);
'''
    try:
        result = subprocess.run(
            ["/usr/bin/php", "-r", php],
            input=password + "\n",
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
            check=False,
            env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL": "C"},
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def _run_helper(args: list[str]) -> dict[str, Any]:
    try:
        result = subprocess.run(
            ["/usr/bin/sudo", "-n", "/usr/local/sbin/msfixit-hardware-action", *args],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
            check=False,
            env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL": "C"},
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return {"ok": False, "error": "helper_unavailable", "detail": str(exc)[:200]}

    try:
        decoded = json.loads(result.stdout.strip() or "{}")
        payload: dict[str, Any] = decoded if isinstance(decoded, dict) else {}
    except json.JSONDecodeError:
        payload = {}
    if result.returncode != 0:
        return {
            "ok": False,
            "error": str(payload.get("error") or "action_failed")[:80],
            "detail": str(payload.get("detail") or result.stderr.strip())[:500],
        }
    payload["ok"] = payload.get("ok") is True
    return payload


def apply_action(action: str, value: str) -> dict[str, Any]:
    allowed = {"set-governor": {"schedutil", "powersave"}}
    if action not in allowed or value not in allowed[action]:
        return {"ok": False, "error": "unsupported_action"}
    return _run_helper(["apply", action, value])


def rollback_action(transaction_id: str) -> dict[str, Any]:
    if not _TXN_RE.fullmatch(transaction_id):
        return {"ok": False, "error": "invalid_transaction"}
    return _run_helper(["rollback", transaction_id])
