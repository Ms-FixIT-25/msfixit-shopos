#!/usr/bin/env bash
set -Eeuo pipefail

artifacts_dir="${1:-artifacts}"
release_kind="${2:-candidate}"
source_commit="${3:-${GITHUB_SHA:-unknown}}"
workflow_run="${4:-${GITHUB_RUN_ID:-unknown}}"

if [ ! -d "$artifacts_dir" ]; then
    echo "Missing artifact directory: $artifacts_dir" >&2
    exit 1
fi

mapfile -t images < <(find "$artifacts_dir" -maxdepth 1 -type f \
    \( -name '*.img.zst' -o -name '*.img.xz' -o -name '*.img.gz' \) \
    -print | sort)

if (( ${#images[@]} != 1 )); then
    echo "Expected exactly one compressed image, found ${#images[@]}." >&2
    exit 1
fi

image="${images[0]}"
image_name="$(basename "$image")"
checksum_file="$artifacts_dir/$image_name.sha256"

if [ ! -s "$checksum_file" ]; then
    echo "Missing checksum file: $checksum_file" >&2
    exit 1
fi

(
    cd "$artifacts_dir"
    sha256sum --check "$(basename "$checksum_file")"
)

image_sha256="$(sha256sum "$image" | awk '{print $1}')"
build_utc="$(date -u +%FT%TZ)"

cat > "$artifacts_dir/release-provenance.json" <<JSON
{
  "schema": 1,
  "product": "Ms. FixIT ShopOS",
  "release_kind": "${release_kind}",
  "source_commit": "${source_commit}",
  "workflow_run": "${workflow_run}",
  "build_utc": "${build_utc}",
  "image": {
    "filename": "${image_name}",
    "sha256": "${image_sha256}"
  }
}
JSON

# Initial machine-readable SBOM foundation. This inventories repository-owned
# runtime payloads and pinned vendor versions. A later hardening phase will add
# a mounted-rootfs package inventory and vulnerability scan.
{
    printf '{\n'
    printf '  "bomFormat": "CycloneDX",\n'
    printf '  "specVersion": "1.5",\n'
    printf '  "version": 1,\n'
    printf '  "metadata": {"component": {"type": "operating-system", "name": "Ms. FixIT ShopOS", "version": "%s"}},\n' "$source_commit"
    printf '  "components": [\n'
    first=1
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        hash="$(sha256sum "$file" | awk '{print $1}')"
        if (( first == 0 )); then printf ',\n'; fi
        first=0
        printf '    {"type":"file","name":"%s","hashes":[{"alg":"SHA-256","content":"%s"}]}' \
            "${file#./}" "$hash"
    done < <(find image/package scripts catalog schemas -type f -print 2>/dev/null | sort)
    printf '\n  ]\n}\n'
} > "$artifacts_dir/shopos-sbom.cdx.json"

sha256sum "$artifacts_dir/release-provenance.json" \
          "$artifacts_dir/shopos-sbom.cdx.json" \
          > "$artifacts_dir/release-metadata.sha256"

printf 'Verified %s image %s for commit %s.\n' "$release_kind" "$image_name" "$source_commit"
