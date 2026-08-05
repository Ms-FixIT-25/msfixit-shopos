# ShopOS Update Center

ShopOS provides a graphical Update Center at `/admin/updates`. It is available through the authenticated local Control Center and linked directly from the ShopOS Store.

## System updates

The operator can manually:

- search the stable GitHub Release for a newer ShopOS version;
- start download and installation from the browser;
- see whether the background update job is active;
- inspect the active A/B slot and transaction state;
- restart the appliance when a trial boot is ready.

The browser never downloads or writes an image itself. A narrow root helper starts the existing signed update agent as a fixed systemd job. The agent verifies the Ed25519-signed manifest, downloads the fixed rootfs asset, checks signed size and SHA-256, writes only the inactive slot, verifies the written bytes and activates a rollback-capable trial boot.

## App updates

The same page searches the latest stable GitHub Release for `.shopos` packages matching apps that are already installed. Downloaded packages enter the fixed app inbox. Installation still passes through the transactional app installer, which verifies the package signature and manifest before replacing an app. Updates can be installed individually or together.

A release app asset must be named exactly after its app identifier:

```text
at.msfixit.shopos.APP_ID.shopos
```

The Update Center ignores packages outside the ShopOS namespace and packages for apps that are not installed. Finding a package does not trust or install it: the signed app installer remains the final authority.

## Privilege boundary

The web user can invoke only these operations:

- `status`
- `check-system`
- `check-apps`
- `start-system-update`
- `reboot`
- `update-app APP_ID`
- `update-all-apps`

The helper validates every app identifier, uses fixed repository and filesystem paths, accepts only allowlisted GitHub HTTPS hosts and never evaluates a browser-supplied shell command.

## Automatic checks

The daily timer remains available. The default configuration checks for updates but does not install system updates automatically:

```json
"auto_apply": false
```

Automatic application should be enabled only after physical update, rollback and power-loss validation.

## Release-side requirement

A usable system release must publish `shopos-update-manifest.json` and `shopos-rootfs.ext4.xz`. App updates are published as signed `.shopos` assets in the same stable release. The private signing keys belong only in protected GitHub Actions secrets and must never be committed or copied to a ShopOS device. The corresponding public keys are embedded in the image.

Until the public system-update key and signed release publisher are provisioned, system updates remain fail-closed. App packages are likewise installed only after their existing signature verification succeeds.
