# Building ShopOS

## Build host

The build uses Raspberry Pi's official `rpi-image-gen` release `v2.6.0` and targets Debian 13 (Trixie) ARM64.

A Debian or Ubuntu build host is recommended. The build script installs the dependencies required by `rpi-image-gen` through its official `install_deps.sh` script and therefore requires `sudo`.

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

The package bundles WP-CLI and the ARM64 Cloudflare Tunnel binary. Their source URLs and checksums are written into `/usr/share/msfixit-shopos/build-info.txt` inside the image.

## Build a flash image

USB SSD:

```bash
make image-usb
```

microSD:

```bash
make image-sd
```

NVMe:

```bash
make image-nvme
```

The resulting compressed image and checksum are copied to `artifacts/`.

## Optional variables

```bash
SHOPOS_VERSION=0.1.0 \
CLOUDFLARED_VERSION=latest \
RPI_IMAGE_GEN_VERSION=v2.6.0 \
make image-usb
```

`CLOUDFLARED_VERSION` can be set to an explicit release tag instead of `latest`.

## GitHub Actions

The `Build ShopOS image` workflow builds the USB SSD image on pushes affecting the image source. A manually dispatched workflow can select `usb`, `sd` or `nvme`.

The workflow runs on GitHub's native ARM64 Ubuntu runner, builds the appliance package, builds the Raspberry Pi image and uploads the flash image with its SHA-256 checksum.
