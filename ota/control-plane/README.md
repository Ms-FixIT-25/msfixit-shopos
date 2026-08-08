# ShopOS OTA control plane

This is the minimal server-side companion to the ShopOS device notification client.

## Security boundary

The control plane does **not** distribute trusted executable content and does not bypass the existing signed update agent. A notification only returns `action=check`; the device then invokes `msfixit-update-agent run`, which independently obtains and verifies signed ShopOS release metadata and artifact checksums.

Terminate public traffic with a production TLS reverse proxy. The reference process defaults to `127.0.0.1:8088` and should not be exposed directly to the Internet.

Set a random admin bearer token of at least 32 characters in `SHOPOS_OTA_ADMIN_TOKEN`. Do not commit it. Device bearer tokens are generated per registration and only SHA-256 token digests are retained server-side.

## API v1

- `POST /v1/devices/register` — register/refresh a device identity and issue a device bearer token.
- `GET /v1/devices/{id}/notifications?wait=N` — authenticated long poll; returns only `check` or `none`.
- `POST /v1/devices/{id}/heartbeat` — authenticated last-seen/version report.
- `POST /v1/devices/{id}/result` — authenticated update state/result report.
- `POST /v1/admin/notify` — admin-only fanout trigger for a `stable` or `candidate` channel, optionally one device.

## Run locally for development

```sh
export SHOPOS_OTA_ADMIN_TOKEN='replace-with-a-random-secret-at-least-32-characters'
python3 shopos_ota_control.py --db /tmp/shopos-ota.sqlite3
```

Production deployment still needs TLS, rate limiting, backups/retention, administrative revocation tooling, observability and release-pipeline integration. Those are intentionally not faked in this MVP.
