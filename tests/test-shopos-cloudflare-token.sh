#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
service="$root/image/package/etc/systemd/system/msfixit-cloudflared.service"
runner="$root/image/package/usr/local/sbin/msfixit-cloudflared-run"

bash -n "$runner"
grep -Fq 'ExecStart=/bin/bash /usr/local/sbin/msfixit-cloudflared-run' "$service"
grep -Fq 'RuntimeDirectory=msfixit-cloudflared' "$service"
grep -Fq 'StartLimitBurst=10' "$service"
grep -Fq 'Restart=on-failure' "$service"
grep -Fq -- '--token-file "$runtime"' "$runner"
grep -Fq 'chmod 0600 "$runtime"' "$runner"
grep -Fq 'unset token line' "$runner"

if grep -Eq 'ExecStart=.*--token[[:space:]]+\$?\{?CF_TUNNEL_TOKEN' "$service"; then
    echo 'Tunnel token must never be passed as a process argument.' >&2
    exit 1
fi
if grep -Fq 'EnvironmentFile=' "$service"; then
    echo 'Secret token environment file must not be injected into cloudflared process environment.' >&2
    exit 1
fi

printf 'PASS: Cloudflare token is materialized as a root-only runtime file and never placed in cloudflared argv.\n'
