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

for cmd in gh jq mktemp awk; do
    command -v "$cmd" >/dev/null || {
        echo "Missing command: $cmd" >&2
        exit 1
    }
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="v${version}"
release_endpoint="repos/${repo}/releases/tags/${tag}"
release_json=""
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

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

delete_asset_id() {
    local id="$1"
    [ -n "$id" ] || return 0
    gh api --method DELETE "repos/${repo}/releases/assets/${id}"
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
        delete_asset_id "$target_id"
    fi

    printf 'Renaming release asset: %s -> %s\n' "$source_name" "$target_name"
    gh api --method PATCH "repos/${repo}/releases/assets/${source_id}" \
        -f name="$target_name" >/dev/null
}

rewrite_checksum_asset() {
    local source_name="$1"
    local target_name="$2"
    local target_payload="$3"
    local source_id target_id download_name download_dir source_file digest output_file

    refresh_release
    source_id="$(asset_id "$source_name")"
    target_id="$(asset_id "$target_name")"

    if [ -n "$source_id" ]; then
        download_name="$source_name"
    elif [ -n "$target_id" ]; then
        download_name="$target_name"
    else
        echo "Required checksum asset is missing: $source_name" >&2
        exit 1
    fi

    download_dir="$work/download-${target_name//[^A-Za-z0-9._-]/_}"
    rm -rf "$download_dir"
    install -d -m 0755 "$download_dir"
    gh release download "$tag" --repo "$repo" \
        --pattern "$download_name" --dir "$download_dir"
    source_file="$download_dir/$download_name"
    test -s "$source_file"

    digest="$(awk 'NF {print $1; exit}' "$source_file")"
    [[ "$digest" =~ ^[0-9a-fA-F]{64}$ ]] || {
        echo "Invalid SHA-256 digest in release asset $download_name" >&2
        exit 1
    }

    output_file="$work/$target_name"
    printf '%s  %s\n' "${digest,,}" "$target_payload" > "$output_file"

    # Only tiny checksum files are downloaded and replaced. Multi-gigabyte
    # image assets are renamed server-side through the release asset API.
    if [ -n "$source_id" ]; then
        delete_asset_id "$source_id"
    fi
    if [ -n "$target_id" ] && [ "$target_id" != "$source_id" ]; then
        delete_asset_id "$target_id"
    fi
    gh release upload "$tag" "$output_file" --repo "$repo" --clobber
}

verify_checksum_asset() {
    local checksum_name="$1"
    local payload_name="$2"
    local verify_dir="$work/verify-${checksum_name//[^A-Za-z0-9._-]/_}"
    rm -rf "$verify_dir"
    install -d -m 0755 "$verify_dir"
    gh release download "$tag" --repo "$repo" \
        --pattern "$checksum_name" --dir "$verify_dir"
    grep -Eq "^[0-9a-f]{64}  ${payload_name//./\.}$" "$verify_dir/$checksum_name"
}

base="msfixit-shopos-${version}-rpi4-usb"
desktop_asset="${base}-windows-macos.zip"
linux_asset="${base}-linux.img.xz"
desktop_checksum="${desktop_asset}.sha256"
linux_checksum="${linux_asset}.sha256"

rename_asset 'msfixit-shopos-rpi4-usb.img.zip' "$desktop_asset"
rename_asset 'msfixit-shopos-rpi4-usb.img.xz' "$linux_asset"
rewrite_checksum_asset \
    'msfixit-shopos-rpi4-usb.img.zip.sha256' \
    "$desktop_checksum" \
    "$desktop_asset"
rewrite_checksum_asset \
    'msfixit-shopos-rpi4-usb.img.xz.sha256' \
    "$linux_checksum" \
    "$linux_asset"
rename_asset 'msfixit-shopos-rpi4-usb.ab-layout' "${base}.ab-layout"
rename_asset 'SHOPOS-VERSION.txt' "SHOPOS-${version}-VERSION.txt"

notes_file="$work/release-notes.md"
bash "$root/scripts/render-release-notes.sh" "$version" > "$notes_file"
gh release edit "$tag" --repo "$repo" \
    --title "Ms. FixIT ShopOS ${version}" \
    --notes-file "$notes_file"

refresh_release
required=(
    "$desktop_asset"
    "$desktop_checksum"
    "$linux_asset"
    "$linux_checksum"
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

verify_checksum_asset "$desktop_checksum" "$desktop_asset"
verify_checksum_asset "$linux_checksum" "$linux_asset"

printf 'Release %s now uses exact versioned, platform-specific download names.\n' "$tag"
