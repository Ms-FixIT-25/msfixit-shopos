#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device="${1:-rpi4}"
storage="${2:-usb}"
rig_version="${RPI_IMAGE_GEN_VERSION:-v2.6.0}"
rig_dir="${RPI_IMAGE_GEN_DIR:-${root}/.cache/rpi-image-gen-${rig_version}}"
artifacts_dir="${root}/artifacts"
source_image_name="msfixit-shopos-${device}-${storage}"
config_name="shopos-${device}-${storage}.yaml"
build_desktop_zip="${SHOPOS_BUILD_DESKTOP_ZIP:-1}"
xz_level="${SHOPOS_XZ_LEVEL:-6}"
artifact_version="${SHOPOS_ARTIFACT_VERSION:-}"

# Pull requests need a bootable, checksummed QEMU candidate, not the second
# desktop ZIP intended for published Windows/macOS releases. Keep official and
# manual builds unchanged while making every PR build fast by default.
if [ "${GITHUB_EVENT_NAME:-}" = pull_request ]; then
    build_desktop_zip="${SHOPOS_BUILD_DESKTOP_ZIP:-0}"
    xz_level="${SHOPOS_XZ_LEVEL:-1}"
fi

case "$device" in rpi4|rpi5) ;; *) echo "Usage: $0 [rpi4|rpi5] [usb|sd|nvme]" >&2; exit 2;; esac
case "$storage" in usb|sd|nvme) ;; *) echo "Usage: $0 [rpi4|rpi5] [usb|sd|nvme]" >&2; exit 2;; esac
case "$build_desktop_zip" in 0|1) ;; *) echo 'SHOPOS_BUILD_DESKTOP_ZIP must be 0 or 1.' >&2; exit 2;; esac
case "$xz_level" in 0|1|2|3|4|5|6|7|8|9) ;; *) echo 'SHOPOS_XZ_LEVEL must be an integer from 0 to 9.' >&2; exit 2;; esac
if [ "$device" = rpi4 ] && [ "$storage" = nvme ]; then
    echo "Raspberry Pi 4B has no native NVMe target; use usb for an NVMe USB enclosure." >&2
    exit 2
fi
[ -f "${root}/image/config/${config_name}" ] || { echo "Missing image configuration: image/config/${config_name}" >&2; exit 1; }
[ -f "${root}/image/VERSION" ] || { echo 'Missing image/VERSION.' >&2; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "ShopOS images must be built on a native ARM64 host." >&2; exit 1; }

# Stable main builds advance monotonically from the latest vMAJOR.MINOR.PATCH
# tag. A manually raised image/VERSION starts a new major/minor line unchanged.
if [ "${GITHUB_EVENT_NAME:-}" = push ] && [ "${GITHUB_REF:-}" = refs/heads/main ]; then
    git -C "$root" fetch --force --tags origin
    release_version="$(bash "${root}/scripts/next-release-version.sh" "${root}/image/VERSION")"
    printf '%s\n' "$release_version" > "${root}/image/VERSION"
    export SHOPOS_VERSION="$release_version"
    artifact_version="$release_version"
    printf 'Automatic ShopOS release version: %s\n' "$release_version"
fi

build_version="${SHOPOS_VERSION:-$(tr -d '[:space:]' < "${root}/image/VERSION")}"
[[ "$build_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
    echo "Invalid ShopOS build version: $build_version" >&2
    exit 1
}
export SHOPOS_VERSION="$build_version"

image_name="$source_image_name"
if [ -n "$artifact_version" ]; then
    [[ "$artifact_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
        echo "Invalid SHOPOS_ARTIFACT_VERSION: $artifact_version" >&2
        exit 1
    }
    image_name="msfixit-shopos-${artifact_version}-${device}-${storage}"
fi

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
    sudo apt-get install -y fdisk e2fsprogs util-linux xz-utils zip pv
    sudo chmod o+x "$HOME"
    (cd "$rig_dir" && sudo ./install_deps.sh)
fi

(cd "$rig_dir" && ./rpi-image-gen build -S "${root}/image" -c "$config_name")

deploy_dir="$(find "$rig_dir/work" -maxdepth 1 -type d -name 'deploy-*' -printf '%T@ %p\n' | sort -nr | awk 'NR==1 {$1=""; sub(/^ /, ""); print}')"
[ -n "$deploy_dir" ] && [ -d "$deploy_dir" ] || { echo 'The image build completed without a deploy directory.' >&2; exit 1; }

image_file="$(find "$deploy_dir" -maxdepth 1 -type f \( -name "${source_image_name}.img.zst" -o -name "${source_image_name}.img.xz" -o -name "${source_image_name}.img.gz" \) ! -name '*.sparse.*' -print -quit)"
[ -n "$image_file" ] && [ -f "$image_file" ] || { echo 'The image build completed without a compressed deploy image.' >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
raw="$work/${source_image_name}.img"
printf 'Unpacking base image: %s\n' "$image_file"
case "$image_file" in
    *.img.xz) pv --force --bytes --timer --eta --rate "$image_file" | xz --decompress --stdout > "$raw" ;;
    *.img.zst) pv --force --bytes --timer --eta --rate "$image_file" | zstd --decompress --stdout > "$raw" ;;
    *.img.gz) pv --force --bytes --timer --eta --rate "$image_file" | gzip --decompress --stdout > "$raw" ;;
    *) echo 'unsupported image compression' >&2; exit 1 ;;
esac

sudo bash "${root}/scripts/postprocess-ab-image.sh" "$raw"

rm -rf "$artifacts_dir"
install -d -m 0755 "$artifacts_dir"
output="$artifacts_dir/${image_name}.img.xz"
desktop_output="$artifacts_dir/${image_name}.img.zip"
desktop_raw="$work/desktop/${image_name}.img"
raw_size="$(stat -c '%s' "$raw")"
xz_preset="-${xz_level}"

printf 'Compressing %s-byte A/B image to XZ preset %s...\n' "$raw_size" "$xz_level"
pv --force --bytes --timer --eta --rate --size "$raw_size" "$raw" \
    | xz --threads=0 "$xz_preset" --check=crc64 --compress --stdout \
    > "$output"
printf 'XZ candidate complete: %s\n' "$output"

if [ "$build_desktop_zip" = 1 ]; then
    # A/B post-processing grows the image after its initial creation. Some
    # Windows and macOS extractors preserve the resulting zero ranges as sparse
    # holes. Raspberry Pi Imager 2.x can then display more than 200 percent.
    # Official releases therefore keep a deliberately dense ZIP64 image.
    printf 'Creating dense Windows/macOS image copy...\n'
    install -d -m 0755 "$(dirname "$desktop_raw")"
    cp --sparse=never "$raw" "$desktop_raw"
    printf 'Compressing dense desktop image to ZIP64...\n'
    (
        cd "$(dirname "$desktop_raw")"
        zip -9 "$desktop_output" "$(basename "$desktop_raw")"
    )
    printf 'Desktop ZIP complete: %s\n' "$desktop_output"
else
    printf 'Skipping desktop ZIP for this candidate build; official release builds keep it enabled.\n'
fi

cp "${raw}.ab-layout" "$artifacts_dir/${image_name}.ab-layout"
printf '%s\n' "$build_version" > "$artifacts_dir/SHOPOS-VERSION.txt"
(
    cd "$artifacts_dir"
    sha256sum "$(basename "$output")" > "$(basename "$output").sha256"
    if [ "$build_desktop_zip" = 1 ]; then
        sha256sum "$(basename "$desktop_output")" > "$(basename "$desktop_output").sha256"
    fi
)

printf 'Version:       %s\n' "$build_version"
printf 'Device:        %s\n' "$device"
printf 'Storage:       %s\n' "$storage"
printf 'A/B image:     %s\n' "$output"
printf 'Layout:        %s\n' "$artifacts_dir/${image_name}.ab-layout"
printf 'Version file:  %s\n' "$artifacts_dir/SHOPOS-VERSION.txt"
printf 'Checksum:      %s\n' "$output.sha256"
if [ "$build_desktop_zip" = 1 ]; then
    printf 'Desktop image: %s\n' "$desktop_output"
    printf 'Desktop SHA:   %s\n' "$desktop_output.sha256"
fi
