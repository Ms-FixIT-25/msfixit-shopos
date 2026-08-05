#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device="${1:-rpi4}"
storage="${2:-usb}"
rig_version="${RPI_IMAGE_GEN_VERSION:-v2.6.0}"
rig_dir="${RPI_IMAGE_GEN_DIR:-${root}/.cache/rpi-image-gen-${rig_version}}"
artifacts_dir="${root}/artifacts"
image_name="msfixit-shopos-${device}-${storage}"
config_name="shopos-${device}-${storage}.yaml"

case "$device" in rpi4|rpi5) ;; *) echo "Usage: $0 [rpi4|rpi5] [usb|sd|nvme]" >&2; exit 2;; esac
case "$storage" in usb|sd|nvme) ;; *) echo "Usage: $0 [rpi4|rpi5] [usb|sd|nvme]" >&2; exit 2;; esac
if [ "$device" = rpi4 ] && [ "$storage" = nvme ]; then
    echo "Raspberry Pi 4B has no native NVMe target; use usb for an NVMe USB enclosure." >&2
    exit 2
fi
[ -f "${root}/image/config/${config_name}" ] || { echo "Missing image configuration: image/config/${config_name}" >&2; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "ShopOS images must be built on a native ARM64 host." >&2; exit 1; }

bash "${root}/scripts/build-package.sh"
sha256sum --check "${root}/image/packages/msfixit-shopos_arm64.deb.sha256"

if [ ! -d "$rig_dir/.git" ]; then
    rm -rf "$rig_dir"
    install -d -m 0755 "$(dirname "$rig_dir")"
    git clone --depth 1 --branch "$rig_version" https://github.com/raspberrypi/rpi-image-gen.git "$rig_dir"
else
    git -C "$rig_dir" fetch --depth 1 --force origin "refs/tags/${rig_version}:refs/tags/${rig_version}"
    git -C "$rig_dir" checkout --force "$rig_version"
fi

if [ "$rig_version" = v2.6.0 ] && [ "$storage" = usb ]; then
    usb_schema_patch="${root}/patches/rpi-image-gen-v2.6.0-idp-usb.patch"
    git -C "$rig_dir" apply --check "$usb_schema_patch"
    git -C "$rig_dir" apply "$usb_schema_patch"
fi

if [ "${SHOPOS_SKIP_BUILD_DEPS:-0}" != 1 ]; then
    sudo apt-get update
    sudo apt-get install -y fdisk e2fsprogs util-linux xz-utils
    sudo chmod o+x "$HOME"
    (cd "$rig_dir" && sudo ./install_deps.sh)
fi

(cd "$rig_dir" && ./rpi-image-gen build -S "${root}/image" -c "$config_name")

deploy_dir="$(find "$rig_dir/work" -maxdepth 1 -type d -name 'deploy-*' -printf '%T@ %p\n' | sort -nr | awk 'NR==1 {$1=""; sub(/^ /, ""); print}')"
[ -n "$deploy_dir" ] && [ -d "$deploy_dir" ] || { echo 'The image build completed without a deploy directory.' >&2; exit 1; }

image_file="$(find "$deploy_dir" -maxdepth 1 -type f \( -name "${image_name}.img.zst" -o -name "${image_name}.img.xz" -o -name "${image_name}.img.gz" \) ! -name '*.sparse.*' -print -quit)"
[ -n "$image_file" ] && [ -f "$image_file" ] || { echo 'The image build completed without a compressed deploy image.' >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
raw="$work/${image_name}.img"
case "$image_file" in
    *.img.xz) xz --decompress --stdout "$image_file" > "$raw" ;;
    *.img.zst) zstd --decompress --stdout "$image_file" > "$raw" ;;
    *.img.gz) gzip --decompress --stdout "$image_file" > "$raw" ;;
    *) echo 'unsupported image compression' >&2; exit 1 ;;
esac

sudo bash "${root}/scripts/postprocess-ab-image.sh" "$raw"

rm -rf "$artifacts_dir"
install -d -m 0755 "$artifacts_dir"
output="$artifacts_dir/${image_name}.img.xz"
xz --threads=0 --check=crc64 --compress --stdout "$raw" > "$output"
cp "${raw}.ab-layout" "$artifacts_dir/${image_name}.ab-layout"
(
    cd "$artifacts_dir"
    sha256sum "$(basename "$output")" > "$(basename "$output").sha256"
)

printf 'Device:      %s\n' "$device"
printf 'Storage:     %s\n' "$storage"
printf 'A/B image:   %s\n' "$output"
printf 'Layout:      %s\n' "$artifacts_dir/${image_name}.ab-layout"
printf 'Checksum:    %s\n' "$output.sha256"
