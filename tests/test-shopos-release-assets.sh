#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
renderer="$root/scripts/render-release-notes.sh"
syncer="$root/scripts/sync-release-assets.sh"
workflow="$root/.github/workflows/release-assets-sync.yml"
acceptance="$root/.github/workflows/production-release.yml"
build_workflow="$root/.github/workflows/build-image.yml"
docs="$root/docs/INSTALL_IMAGE.md"

bash -n "$renderer"
bash -n "$syncer"
test -s "$workflow"
test -s "$acceptance"
test -s "$build_workflow"
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
grep -Fq 'rewrite_checksum_asset' "$syncer"
grep -Fq 'verify_checksum_asset' "$syncer"
grep -Fq 'printf '\''%s  %s\n'\'' "${digest,,}" "$target_payload"' "$syncer"
grep -Fq 'temp_name="${target_name}.new-${GITHUB_RUN_ID:-$$}"' "$syncer"
grep -Fq 'Temporary checksum asset was not uploaded' "$syncer"
grep -Fq 'windows-macos.zip' "$syncer"
grep -Fq 'linux.img.xz' "$syncer"
if grep -Fq -- '--pattern "$desktop_asset"' "$syncer"; then
    echo 'The multi-gigabyte Desktop ZIP must not be downloaded during renaming.' >&2
    exit 1
fi
if grep -Fq -- '--pattern "$linux_asset"' "$syncer"; then
    echo 'The multi-gigabyte Linux image must not be downloaded during renaming.' >&2
    exit 1
fi
if grep -Eq 'curl .*releases/download' "$syncer"; then
    echo 'Release images must not be copied through curl.' >&2
    exit 1
fi

# During PR #80 consolidation, release asset synchronization is deliberately a
# manual repair tool for releases that already exist. It must not publish from
# a build completion event or silently follow stale main CI.
grep -Fq 'workflow_dispatch:' "$workflow"
grep -Fq 'version:' "$workflow"
grep -Fq 'gh release view "v${version}"' "$workflow"
grep -Fq 'scripts/sync-release-assets.sh' "$workflow"
if grep -Fq 'workflow_run:' "$workflow"; then
    echo 'Release asset repair must not auto-run from image-build completion during PR80 consolidation.' >&2
    exit 1
fi
if grep -Fq "head_branch == 'main'" "$workflow"; then
    echo 'Release asset repair must not depend on stale main build metadata during PR80 consolidation.' >&2
    exit 1
fi

# PR #80 is temporarily the authoritative build/test source. Candidate images
# are built from the exact consolidation SHA, while stable publication remains
# disabled until the verified consolidation is deliberately merged to main.
grep -Fq 'branches: [integration/shopos-master-consolidation]' "$acceptance"
grep -Fq 'Test exact PR80 consolidation commit' "$acceptance"
grep -Fq 'Build exact PR80 Raspberry Pi image' "$acceptance"
grep -Fq 'Boot exact PR80 image on ARM64' "$acceptance"
grep -Fq "test \"\$GITHUB_REF\" = 'refs/heads/integration/shopos-master-consolidation'" "$acceptance"
grep -Fq 'Stable publishing is intentionally disabled while PR #80 is the authoritative' "$acceptance"
if grep -Eq 'gh release (create|upload|edit)|Publish boot-verified production release' "$acceptance"; then
    echo 'PR80 acceptance workflow must not publish a stable release.' >&2
    exit 1
fi

grep -Fq 'branches: [integration/shopos-master-consolidation]' "$build_workflow"
grep -Fq 'github.event.pull_request.head.sha || github.sha' "$build_workflow"
if grep -Fq 'branches: [main' "$build_workflow"; then
    echo 'Automatic image builds must use PR80 as the authoritative source during consolidation.' >&2
    exit 1
fi

grep -Fq 'msfixit-shopos-<VERSION>-rpi4-usb-windows-macos.zip' "$docs"
grep -Fq 'msfixit-shopos-<VERSION>-rpi4-usb-linux.img.xz' "$docs"

printf 'PASS: release assets remain versioned while PR80 candidate CI is isolated from stale main publication.\n'
