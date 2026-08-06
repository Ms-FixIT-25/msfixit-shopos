#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
renderer="$root/scripts/render-release-notes.sh"
syncer="$root/scripts/sync-release-assets.sh"
workflow="$root/.github/workflows/release-assets-sync.yml"
docs="$root/docs/INSTALL_IMAGE.md"

bash -n "$renderer"
bash -n "$syncer"
test -s "$workflow"
test -s "$docs"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
notes="$work/notes.md"
bash "$renderer" 0.15.7 > "$notes"

expected=(
    'msfixit-shopos-0.15.7-rpi4-usb-windows-macos.zip'
    'msfixit-shopos-0.15.7-rpi4-usb-windows-macos.zip.sha256'
    'msfixit-shopos-0.15.7-rpi4-usb-linux.img.xz'
    'msfixit-shopos-0.15.7-rpi4-usb-linux.img.xz.sha256'
    'msfixit-shopos-0.15.7-rpi4-usb.ab-layout'
    'SHOPOS-0.15.7-VERSION.txt'
    'msfixit-shopos-0.15.7-rpi4-usb.img'
)
for name in "${expected[@]}"; do
    grep -Fq "$name" "$notes"
done

if grep -Fq '`msfixit-shopos-rpi4-usb.img.zip`' "$notes"; then
    echo 'Release notes must not advertise an unversioned Desktop asset.' >&2
    exit 1
fi
if grep -Fq '`msfixit-shopos-rpi4-usb.img.xz`' "$notes"; then
    echo 'Release notes must not advertise an unversioned Linux asset.' >&2
    exit 1
fi

if bash "$renderer" 01.2.3 >/dev/null 2>&1; then
    echo 'Invalid semantic versions must be rejected by the release-note renderer.' >&2
    exit 1
fi

grep -Fq -- '--method PATCH' "$syncer"
grep -Fq 'releases/assets/' "$syncer"
grep -Fq 'windows-macos.zip' "$syncer"
grep -Fq 'linux.img.xz' "$syncer"
if grep -Eq 'gh release download|curl .*releases/download' "$syncer"; then
    echo 'Release assets must be renamed server-side instead of downloaded and uploaded again.' >&2
    exit 1
fi

grep -Fq 'workflows: ["Build ShopOS image"]' "$workflow"
grep -Fq "head_branch == 'main'" "$workflow"
grep -Fq 'scripts/sync-release-assets.sh' "$workflow"
grep -Fq 'msfixit-shopos-<VERSION>-rpi4-usb-windows-macos.zip' "$docs"
grep -Fq 'msfixit-shopos-<VERSION>-rpi4-usb-linux.img.xz' "$docs"

printf 'PASS: release assets and documentation use exact versioned, platform-specific names.\n'
