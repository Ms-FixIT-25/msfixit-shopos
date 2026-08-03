# Building ShopOS

## Build host

The build uses Raspberry Pi's official `rpi-image-gen` release `v2.6.0` and targets Debian 13 (Trixie) ARM64.

Use a native ARM64 Debian Bookworm/Trixie or Ubuntu build host. The build script installs the dependencies required by `rpi-image-gen` through its official `install_deps.sh` script and therefore requires `sudo`.

## Syntax checks

```bash
make check
```

## Build only the appliance package

```bash
make package
```

This creates:

```text
image/packages/msfixit-shopos_arm64.deb
image/packages/msfixit-shopos_arm64.deb.sha256
```

The package bundles pinned and SHA-256-verified WP-CLI and ARM64 Cloudflare Tunnel binaries. Their exact versions, source URLs and checksums are written into `/usr/share/msfixit-shopos/build-info.txt` inside the image.

## Build a Raspberry Pi 4B image

USB SSD or NVMe in a USB enclosure:

```bash
make image-rpi4-usb
```

microSD:

```bash
make image-rpi4-sd
```

## Build a Raspberry Pi 5 image

```bash
make image-rpi5-usb
make image-rpi5-sd
make image-rpi5-nvme
```

The resulting compressed image and portable checksum are copied to `artifacts/`. The hardware model and storage type are always part of the filename.

The low-level command is:

```bash
bash scripts/build-image.sh rpi4 usb
```

Supported combinations:

- `rpi4 usb`
- `rpi4 sd`
- `rpi5 usb`
- `rpi5 sd`
- `rpi5 nvme`

A Pi 4B has no native NVMe target. An NVMe drive connected through a USB enclosure uses `rpi4 usb`.

## Optional variables

```bash
SHOPOS_VERSION=0.1.1 \
RPI_IMAGE_GEN_VERSION=v2.6.0 \
make image-rpi4-usb
```

Cloudflared and WP-CLI are pinned in `scripts/build-package.sh`; changing them also requires updating their trusted SHA-256 values.

## GitHub Actions

The `Build ShopOS image` workflow defaults to a Raspberry Pi 4B USB-SSD image for pushes affecting the image source. A manually dispatched workflow can select the Raspberry Pi model and storage target.

The workflow runs on GitHub's native ARM64 Ubuntu runner, builds the appliance package, builds the selected Raspberry Pi image and uploads the flash image with its SHA-256 checksum. Successful `main` builds of the Pi 4B USB target are published as a versioned GitHub Release.
