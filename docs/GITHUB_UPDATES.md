# ShopOS updates from GitHub

ShopOS checks the latest stable GitHub Release once per day. It never runs `git pull` in the live appliance and never replaces files in the active root filesystem.

## Trust and update flow

1. Fetch the latest published, non-prerelease release from `Ms-FixIT-25/msfixit-shopos`.
2. Require exactly one `shopos-update-manifest.json` and one `shopos-rootfs.ext4.xz` asset.
3. Verify the manifest with the pinned Ed25519 public key at `/usr/share/msfixit-shopos/update/update-signing-public.pem`.
4. Require the signed URL, compressed size and SHA-256 to match the downloaded release asset.
5. Decompress and hash the root filesystem locally.
6. Write it only to the inactive `SHOPOS_ROOT_A` or `SHOPOS_ROOT_B` partition.
7. Read the complete written region back and verify it.
8. Mark the target slot as a trial, switch the real Raspberry Pi kernel command line and reboot.
9. Confirm a healthy trial or automatically return to the previous slot after the configured failed boot limit.

## Commands

```bash
sudo msfixit-update-agent check
sudo msfixit-update-agent apply
sudo msfixit-update-agent apply --no-reboot
systemctl status msfixit-update-agent.timer
journalctl -u msfixit-update-agent.service
```

The default configuration checks for updates but does not install them automatically:

```json
"auto_apply": false
```

Set it to `true` only after physical update, rollback and power-loss validation has passed.

## Release-side requirement

A usable release must publish the separate root filesystem asset and a signed manifest. The private signing key must exist only as a protected GitHub Actions secret. It must never be committed to the repository or copied onto a ShopOS device. The corresponding public key is embedded in the ShopOS image.

Until that public key and the signed release publisher are provisioned, the systemd service is fail-closed through `ConditionPathExists` and no network update is applied.
