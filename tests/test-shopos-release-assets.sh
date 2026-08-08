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

# Release-asset repair remains a manual tool for already-existing releases; it
# must not silently follow build completion or stale main metadata.
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

# PR #80 is the authoritative candidate source. A candidate pre-release is
# allowed only after the exact source has been tested, imaged and ARM64/QEMU
# boot-validated. This workflow must never publish a stable release or rebuild
# from main.
grep -Fq 'branches: [integration/shopos-master-consolidation]' "$acceptance"
grep -Fq 'Test exact PR80 consolidation commit' "$acceptance"
grep -Fq 'Build exact PR80 Raspberry Pi image' "$acceptance"
grep -Fq 'Boot exact PR80 image on ARM64' "$acceptance"
grep -Fq "test \"\$GITHUB_REF\" = 'refs/heads/integration/shopos-master-consolidation'" "$acceptance"
grep -Fq 'Publish boot-verified PR80 candidate' "$acceptance"
grep -Fq 'needs: [validate, image, qemu]' "$acceptance"
grep -Fq 'tag="pr80-v${RELEASE_VERSION}-${SHORT_SHA}"' "$acceptance"
grep -Fq -- '--target "$SOURCE_SHA"' "$acceptance"
grep -Fq -- '--prerelease' "$acceptance"
grep -Fq 'test "$target" = "$SOURCE_SHA"' "$acceptance"
grep -Fq 'This download is a Pre-Release and not a final production release' "$acceptance" || grep -Fq 'Dieser Download ist ein Pre-Release und noch kein finaler Produktionsrelease' "$acceptance"
if grep -Eq 'tag="v\$\{RELEASE_VERSION\}"|--latest|Publish boot-verified production release' "$acceptance"; then
    echo 'PR80 acceptance must publish only a SHA-bound pre-release, never a stable/latest release.' >&2
    exit 1
fi

# Automatic push builds remain restricted to the integration branch. Pull
# requests may target main as an additional validation path, but this must not
# turn main into an automatic image publication source.
grep -Fq 'branches: [integration/shopos-master-consolidation]' "$build_workflow"
grep -Fq 'branches: [main, integration/shopos-master-consolidation]' "$build_workflow"
grep -Fq 'github.event.pull_request.head.sha || github.sha' "$build_workflow"
python3 - "$build_workflow" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
push, rest = text.split('  pull_request:\n', 1)
if 'branches: [main' in push:
    raise SystemExit('Automatic push image builds must not use main during PR80 consolidation.')
if 'branches: [main, integration/shopos-master-consolidation]' not in rest:
    raise SystemExit('PR image validation must cover both main and the integration branch.')
PY

grep -Fq 'msfixit-shopos-<VERSION>-rpi4-usb-windows-macos.zip' "$docs"
grep -Fq 'msfixit-shopos-<VERSION>-rpi4-usb-linux.img.xz' "$docs"

printf 'PASS: release assets remain versioned and PR80 publishing is limited to exact boot-verified pre-releases.\n'
