# ShopOS OTA notification protocol v1

The notification plane is intentionally separate from the trusted update plane.
A notification can only request that a device run its existing signed update
check. It can never supply executable content, release metadata to trust, a
rootfs URL to trust, or a command to execute.

## Device registration

`POST /v1/devices/register`

Request fields:
- `schema`: `1`
- `device_id`: locally generated UUID
- `client_instance`: random per-installation identifier
- `architecture`: device architecture reported by the OS
- `shopos_version`: locally installed ShopOS version
- `channel`: `stable` or `candidate`

The service returns an opaque random device token of at least 256 bits. The token
must only be stored in the root-owned ShopOS update state and must never be
published in GitHub artifacts or logs.

Initial registration is a bootstrap operation authenticated by the server's TLS
identity. Production deployment of the control plane must additionally rate-limit
registration and support device revocation. A future enrollment mechanism may add
stronger operator-approved bootstrap without changing the notification trust
boundary.

## Long-poll notification

`GET /v1/devices/{device_id}/notifications?wait=<seconds>`

Header:
`Authorization: Bearer <device token>`

A valid wake response is intentionally tiny:

```json
{"schema":1,"action":"check","nonce":"unguessable-or-unique-notification-id"}
```

The device rejects malformed actions, duplicate nonces, and wakes that violate the
local minimum interval. Any accepted wake invokes only:

`msfixit-update-agent run`

The existing signed update agent then independently obtains and verifies release
metadata, signed manifest, hash, size and A/B update state.

## Failure behavior

- Notification/control-plane outage never disables the existing GitHub polling timer.
- The client backs off after control-plane failures.
- Replayed notifications are ignored.
- HTTP endpoints are rejected; the control plane must be reached via HTTPS.
- Notifications do not bypass the signed manifest or checksum verification path.

## Deployment gate

The packaged client is disabled by default until a production OTA control-plane
origin is deployed and configured. Enabling it requires a concrete HTTPS endpoint,
control-plane rate limiting, device-token revocation, and regression validation.
This keeps existing signed GitHub polling as the safe fallback while the push-style
control plane is introduced incrementally.
