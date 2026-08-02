#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
storage="${1:-usb}"
rig_version="${RPI_IMAGE_GEN_VERSION:-v2.6.0}"
rig_dir="${RPI_IMAGE_GEN_DIR:-${root}/.cache/rpi-image-gen-${rig_version}}"
artifacts_dir="${root}/artifacts"

case "$storage" in
    usb|sd|nvme) ;;
    *)
        echo "Usage: $0 [usb|sd|nvme]" >&2
        exit 2
        ;;
esac

if [ "$(uname -m)" != "aarch64" ]; then
    echo "ShopOS images must be built on a native ARM64 host." >&2
    exit 1
fi

bash "${root}/scripts/build-package.sh"
sha256sum --check "${root}/image/packages/msfixit-shopos_arm64.deb.sha256"

if [ ! -d "$rig_dir/.git" ]; then
    rm -rf "$rig_dir"
    install -d -m 0755 "$(dirname "$rig_dir")"
    git clone --depth 1 --branch "$rig_version" \
        https://github.com/raspberrypi/rpi-image-gen.git "$rig_dir"
else
    git -C "$rig_dir" fetch --depth 1 --force origin \
        "refs/tags/${rig_version}:refs/tags/${rig_version}"
    git -C "$rig_dir" checkout --force "$rig_version"
fi

if [ "${SHOPOS_SKIP_BUILD_DEPS:-0}" != "1" ]; then
    sudo apt-get update
    sudo chmod o+x "$HOME"
    (
        cd "$rig_dir"
        sudo ./install_deps.sh
    )
fi

(
    cd "$rig_dir"
    ./rpi-image-gen build \
        -S "${root}/image" \
        -c "shopos-rpi5-${storage}.yaml"
)

image_file="$(
    find "$rig_dir" -type f \
        \( -name '*.img' -o -name '*.img.xz' -o -name '*.img.zst' -o -name '*.img.gz' \) \
        -printf '%T@ %p\n' \
        | sort -nr \
        | awk 'NR==1 {$1=""; sub(/^ /, ""); print}'
)"

if [ -z "$image_file" ] || [ ! -f "$image_file" ]; then
    echo "The image build completed without a discoverable image file." >&2
    exit 1
fi

rm -rf "$artifacts_dir"
install -d -m 0755 "$artifacts_dir"
cp "$image_file" "$artifacts_dir/"
sha256sum "$artifacts_dir/$(basename "$image_file")" \
    > "$artifacts_dir/$(basename "$image_file").sha256"

printf 'Flash image: %s\n' "$artifacts_dir/$(basename "$image_file")"
printf 'Checksum:    %s\n' "$artifacts_dir/$(basename "$image_file").sha256"
