#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
storage="${1:-usb}"
rig_version="${RPI_IMAGE_GEN_VERSION:-v2.6.0}"
rig_dir="${RPI_IMAGE_GEN_DIR:-${root}/.cache/rpi-image-gen-${rig_version}}"
artifacts_dir="${root}/artifacts"
image_name="msfixit-shopos-rpi5-${storage}"

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

# rpi-image-gen v2.6.0 allows device.storage_type=usb in its layer metadata,
# but its IDP v2 JSON schema accidentally omits usb. Apply the repository's
# audited compatibility patch so USB-attached SSD/NVMe images retain correct
# metadata instead of being mislabeled as SD media.
if [ "$rig_version" = "v2.6.0" ]; then
    usb_schema_patch="${root}/patches/rpi-image-gen-v2.6.0-idp-usb.patch"
    git -C "$rig_dir" apply --check "$usb_schema_patch"
    git -C "$rig_dir" apply "$usb_schema_patch"
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

deploy_dir="$(
    find "$rig_dir/work" -maxdepth 1 -type d -name 'deploy-*' -printf '%T@ %p\n' \
        | sort -nr \
        | awk 'NR==1 {$1=""; sub(/^ /, ""); print}'
)"

if [ -z "$deploy_dir" ] || [ ! -d "$deploy_dir" ]; then
    echo "The image build completed without a deploy directory." >&2
    exit 1
fi

image_file="$(
    find "$deploy_dir" -maxdepth 1 -type f \
        \( -name "${image_name}.img" \
           -o -name "${image_name}.img.xz" \
           -o -name "${image_name}.img.zst" \
           -o -name "${image_name}.img.gz" \) \
        -print -quit
)"

if [ -z "$image_file" ] || [ ! -f "$image_file" ]; then
    echo "The image build completed but no flash image was found in $deploy_dir." >&2
    exit 1
fi

rm -rf "$artifacts_dir"
install -d -m 0755 "$artifacts_dir"
cp "$image_file" "$artifacts_dir/"
sha256sum "$artifacts_dir/$(basename "$image_file")" \
    > "$artifacts_dir/$(basename "$image_file").sha256"

printf 'Flash image: %s\n' "$artifacts_dir/$(basename "$image_file")"
printf 'Checksum:    %s\n' "$artifacts_dir/$(basename "$image_file").sha256"
