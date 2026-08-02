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

bash "${root}/scripts/build-package.sh"

if [ ! -d "$rig_dir/.git" ]; then
    rm -rf "$rig_dir"
    install -d -m 0755 "$(dirname "$rig_dir")"
    git clone --depth 1 --branch "$rig_version" \
        https://github.com/raspberrypi/rpi-image-gen.git "$rig_dir"
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

# Publish only the compressed flash image produced in a deploy directory.
# The build tree also contains a 10 GiB raw image and Android sparse images;
# neither belongs in the downloadable GitHub artifact.
image_file="$(
    find "$rig_dir/work" -mindepth 2 -maxdepth 2 -type f \
        -path "$rig_dir/work/deploy-*/*" \
        \( -name 'msfixit-shopos-*.img.zst' \
           -o -name 'msfixit-shopos-*.img.xz' \
           -o -name 'msfixit-shopos-*.img.gz' \) \
        ! -name '*.sparse.*' \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr \
        | awk 'NR==1 {$1=""; sub(/^ /, ""); print}'
)"

if [ -z "$image_file" ] || [ ! -f "$image_file" ]; then
    echo "The image build completed without a compressed deploy image." >&2
    exit 1
fi

rm -rf "$artifacts_dir"
install -d -m 0755 "$artifacts_dir"
cp "$image_file" "$artifacts_dir/"
sha256sum "$artifacts_dir/$(basename "$image_file")" \
    > "$artifacts_dir/$(basename "$image_file").sha256"

printf 'Flash image: %s\n' "$artifacts_dir/$(basename "$image_file")"
printf 'Checksum:    %s\n' "$artifacts_dir/$(basename "$image_file").sha256"
