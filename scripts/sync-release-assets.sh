#!/usr/bin/env bash
set -Eeuo pipefail

version="${1:?usage: sync-release-assets.sh VERSION [OWNER/REPO]}"
repo="${2:-${GITHUB_REPOSITORY:-}}"
semver_re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ "$version" =~ $semver_re ]] || {
    echo "Invalid ShopOS release version: $version" >&2
    exit 2
}
[[ "$repo" =~ ^[^/]+/[^/]+$ ]] || {
    echo "Repository must be supplied as OWNER/REPO." >&2
    exit 2
}

for cmd in gh jq mktemp; do
    command -v "$cmd" >/dev/null || {
        echo "Missing command: $cmd" >&2
        exit 1
    }
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="v${version}"
release_endpoint="repos/${repo}/releases/tags/${tag}"
release_json=""

refresh_release() {
    release_json="$(gh api "$release_endpoint")"
}

asset_id() {
    local name="$1"
    jq -r --arg name "$name" '.assets[] | select(.name == $name) | .id' <<< "$release_json" | head -n 1
}

asset_exists() {
    [ -n "$(asset_id "$1")" ]
}

rename_asset() {
    local source_name="$1"
    local target_name="$2"
    local source_id target_id

    refresh_release
    source_id="$(asset_id "$source_name")"
    target_id="$(asset_id "$target_name")"

    if [ -z "$source_id" ]; then
        if [ -n "$target_id" ]; then
            printf 'Asset already normalized: %s\n' "$target_name"
            return 0
        fi
        printf 'Required release asset is missing: %s\n' "$source_name" >&2
        exit 1
    fi

    if [ -n "$target_id" ] && [ "$target_id" != "$source_id" ]; then
        printf 'Removing stale target asset before rename: %s\n' "$target_name"
        gh api --method DELETE "repos/${repo}/releases/assets/${target_id}"
    fi

    printf 'Renaming release asset: %s -> %s\n' "$source_name" "$target_name"
    gh api --method PATCH "repos/${repo}/releases/assets/${source_id}" \
        -f name="$target_name" >/dev/null
}

base="msfixit-shopos-${version}-rpi4-usb"
rename_asset 'msfixit-shopos-rpi4-usb.img.zip' "${base}-windows-macos.zip"
rename_asset 'msfixit-shopos-rpi4-usb.img.zip.sha256' "${base}-windows-macos.zip.sha256"
rename_asset 'msfixit-shopos-rpi4-usb.img.xz' "${base}-linux.img.xz"
rename_asset 'msfixit-shopos-rpi4-usb.img.xz.sha256' "${base}-linux.img.xz.sha256"
rename_asset 'msfixit-shopos-rpi4-usb.ab-layout' "${base}.ab-layout"
rename_asset 'SHOPOS-VERSION.txt' "SHOPOS-${version}-VERSION.txt"

notes_file="$(mktemp)"
trap 'rm -f "$notes_file"' EXIT
bash "$root/scripts/render-release-notes.sh" "$version" > "$notes_file"
gh release edit "$tag" --repo "$repo" \
    --title "Ms. FixIT ShopOS ${version}" \
    --notes-file "$notes_file"

refresh_release
required=(
    "${base}-windows-macos.zip"
    "${base}-windows-macos.zip.sha256"
    "${base}-linux.img.xz"
    "${base}-linux.img.xz.sha256"
    "${base}.ab-layout"
    "SHOPOS-${version}-VERSION.txt"
)
for name in "${required[@]}"; do
    if ! asset_exists "$name"; then
        echo "Release normalization verification failed: $name" >&2
        exit 1
    fi
done

legacy=(
    'msfixit-shopos-rpi4-usb.img.zip'
    'msfixit-shopos-rpi4-usb.img.zip.sha256'
    'msfixit-shopos-rpi4-usb.img.xz'
    'msfixit-shopos-rpi4-usb.img.xz.sha256'
    'msfixit-shopos-rpi4-usb.ab-layout'
    'SHOPOS-VERSION.txt'
)
for name in "${legacy[@]}"; do
    if asset_exists "$name"; then
        echo "Legacy unversioned asset still exists: $name" >&2
        exit 1
    fi
done

printf 'Release %s now uses exact versioned, platform-specific download names.\n' "$tag"
