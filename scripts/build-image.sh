#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=${RPI_IMAGE_GEN_VERSION:-v2.6.0}
cache_dir=${RPI_IMAGE_GEN_DIR:-"$repo_root/.cache/rpi-image-gen"}
artifact_dir=${ARTIFACT_DIR:-"$repo_root/artifacts"}
image_name=msfixit-shopos-rpi5

if [[ $(uname -m) != aarch64 ]]; then
    echo "This build is intended for a native ARM64 Debian/Raspberry Pi OS host." >&2
    exit 1
fi

if [[ ! -d "$cache_dir/.git" ]]; then
    mkdir -p "$(dirname "$cache_dir")"
    git clone --depth 1 --branch "$version" https://github.com/raspberrypi/rpi-image-gen.git "$cache_dir"
fi

git -C "$cache_dir" fetch --depth 1 origin "refs/tags/$version:refs/tags/$version"
git -C "$cache_dir" checkout --force "$version"

sudo "$cache_dir/install_deps.sh"

"$cache_dir/rpi-image-gen" metadata --lint "$repo_root/image/layer/msfixit-shopos.yaml"
"$cache_dir/rpi-image-gen" build \
    -S "$repo_root/image" \
    -c shopos-rpi5.yaml

image_path=$(find "$cache_dir/work" -type f -name "$image_name.img" -print -quit)
if [[ -z "$image_path" ]]; then
    echo "Build completed but $image_name.img was not found." >&2
    exit 1
fi

mkdir -p "$artifact_dir"
xz -T0 -9e -c "$image_path" >"$artifact_dir/$image_name.img.xz"
sha256sum "$artifact_dir/$image_name.img.xz" >"$artifact_dir/$image_name.img.xz.sha256"

echo "Flash image: $artifact_dir/$image_name.img.xz"
echo "Checksum:    $artifact_dir/$image_name.img.xz.sha256"
