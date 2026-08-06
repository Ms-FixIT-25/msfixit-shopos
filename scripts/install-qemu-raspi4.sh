#!/usr/bin/env bash
set -Eeuo pipefail

readonly qemu_version='9.2.4'
readonly qemu_sha512='5aa2ea23d234dd896de73f778defde93f3b490bd22947c396091fdd2231ce5ccd17767c910170a952be88a5593725f1c31b15a6d19b3d30637465d17fb69651c'
readonly source_url="https://download.qemu.org/qemu-${qemu_version}.tar.xz"
readonly prefix="${1:?usage: install-qemu-raspi4.sh PREFIX}"
readonly qemu_binary="$prefix/bin/qemu-system-aarch64"

has_raspi4b() {
    [ -x "$qemu_binary" ] \
        && "$qemu_binary" -machine help 2>/dev/null \
            | grep -Eq '^[[:space:]]*raspi4b([[:space:]]|$)'
}

if has_raspi4b; then
    "$qemu_binary" --version
    printf 'Pinned QEMU already installed at %s\n' "$qemu_binary"
    exit 0
fi

sudo apt-get -o Acquire::Retries=3 update
sudo apt-get -o Acquire::Retries=3 install --yes \
    build-essential curl libfdt-dev libglib2.0-dev libpixman-1-dev \
    meson ninja-build pkg-config python3 python3-venv zlib1g-dev

work_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

archive="$work_dir/qemu-${qemu_version}.tar.xz"
curl --fail --location --retry 5 --retry-all-errors \
    --output "$archive" "$source_url"
printf '%s  %s\n' "$qemu_sha512" "$archive" | sha512sum --check --strict

tar -C "$work_dir" -xf "$archive"
source_dir="$work_dir/qemu-${qemu_version}"
mkdir -p "$source_dir/build" "$prefix"

(
    cd "$source_dir/build"
    ../configure \
        --prefix="$prefix" \
        --target-list=aarch64-softmmu \
        --disable-werror \
        --disable-docs \
        --disable-gtk \
        --disable-sdl \
        --disable-vnc \
        --disable-curses \
        --disable-opengl \
        --disable-spice \
        --disable-slirp
    ninja -j"$(nproc)"
    ninja install
)

if ! has_raspi4b; then
    echo 'Built QEMU does not provide the required raspi4b machine.' >&2
    "$qemu_binary" -machine help >&2 || true
    exit 1
fi

"$qemu_binary" --version
printf 'PASS: installed pinned QEMU %s with raspi4b support.\n' "$qemu_version"
