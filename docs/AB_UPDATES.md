# ShopOS signed A/B update contract

## Purpose

ShopOS updates are modeled as a fail-closed transaction between two operating-system slots, `A` and `B`. The currently active slot is never overwritten in place. A new release is staged into the inactive slot, booted as a trial and confirmed only after the system health gate succeeds.

This first implementation provides the signed manifest verifier, anti-replay rules, persistent transaction state, bounded trial boots and automatic rollback decision. Physical partition switching and image writing are intentionally kept outside this runtime until the Raspberry Pi storage layout is validated on real hardware.

## Signed manifest

The update envelope contains exactly two fields:

```json
{
  "payload": {},
  "signature": "base64 Ed25519 signature"
}
```

The signature covers canonical JSON with sorted keys and no insignificant whitespace. Unknown fields are rejected. The payload binds:

- release version and monotonic sequence;
- minimum supported source sequence;
- Raspberry Pi target;
- HTTPS image URL;
- image size and SHA-256;
- issue and expiry timestamps.

Private signing keys are never stored in ShopOS or in this repository. The device contains only the trusted public key.

## State transitions

```text
idle/confirmed
      |
      | signed manifest, anti-replay and migration floor pass
      v
    staged  -- activate inactive slot -->  trial
                                            |  \
                               health pass  |   \ max boot attempts
                                            v    v
                                      confirmed  rollback
                                                     |
                                                     v
                                                   idle
```

A trial slot receives at most three unconfirmed boots by default. Once that threshold is reached, the state machine selects the previous slot and records `rollback`. The bootloader integration must apply that decision atomically before the next boot.

## Security properties

- strict schema; unknown fields fail closed;
- Ed25519 verification through OpenSSL;
- HTTPS-only source URL;
- image SHA-256 and exact byte count bound into the signature;
- monotonic sequence prevents downgrade and replay;
- migration floor prevents unsupported jumps;
- atomic state writes with file and directory `fsync`;
- only slots `A` and `B` exist;
- no arbitrary device path, shell command or package manager argument is accepted.

## Remaining hardware integration

Before this can update customer devices, a later PR must add and validate:

1. explicit persistent-data and A/B root partitions in every supported image target;
2. a fixed privileged writer that only writes the verified inactive partition;
3. bootloader slot selection and boot-count storage;
4. health confirmation after MariaDB, Redis, Nginx, PHP-FPM and ShopOS migrations pass;
5. power-loss tests during download, write, switch and first trial boot;
6. recovery UI and an operator-visible audit log.

Until those items are complete, the runtime is a verified control-plane foundation, not a production updater.
