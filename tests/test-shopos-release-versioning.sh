#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
calculator="$root/scripts/next-release-version.sh"
builder="$root/scripts/build-image.sh"

bash -n "$calculator"
bash -n "$builder"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
version_file="$work/VERSION"

assert_next() {
    local base="$1"
    local latest="$2"
    local expected="$3"
    local actual

    printf '%s\n' "$base" > "$version_file"
    actual="$(bash "$calculator" "$version_file" "$latest")"
    if [ "$actual" != "$expected" ]; then
        printf 'Expected next version %s for base=%s latest=%s, got %s.\n' \
            "$expected" "$base" "$latest" "$actual" >&2
        exit 1
    fi
}

assert_next 0.15.0 none 0.15.0
assert_next 0.15.0 0.15.0 0.15.1
assert_next 0.15.0 v0.15.9 0.15.10
assert_next 0.15.0 0.16.4 0.16.5
assert_next 0.16.0 0.15.9 0.16.0
assert_next 1.0.0 0.99.99 1.0.0

printf '01.2.3\n' > "$version_file"
if bash "$calculator" "$version_file" none >/dev/null 2>&1; then
    echo 'Invalid semantic versions must be rejected.' >&2
    exit 1
fi

grep -Fq 'next-release-version.sh' "$builder"
grep -Fq 'GITHUB_EVENT_NAME:-' "$builder"
grep -Fq 'refs/heads/main' "$builder"
grep -Fq 'SHOPOS_ARTIFACT_VERSION' "$builder"
grep -Fq 'SHOPOS-VERSION.txt' "$builder"

printf 'PASS: ShopOS release versions advance monotonically and preserve manual major/minor bumps.\n'
