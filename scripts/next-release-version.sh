#!/usr/bin/env bash
set -Eeuo pipefail

version_file="${1:-image/VERSION}"
latest_override="${2:-}"

semver_re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

read_version() {
    local file="$1"
    [ -f "$file" ] || {
        echo "Version file not found: $file" >&2
        exit 1
    }

    local value
    value="$(tr -d '[:space:]' < "$file")"
    [[ "$value" =~ $semver_re ]] || {
        echo "Invalid ShopOS version in $file: $value" >&2
        exit 1
    }
    printf '%s\n' "$value"
}

version_gt() {
    local left="$1"
    local right="$2"
    [ "$left" != "$right" ] &&
        [ "$(printf '%s\n%s\n' "$left" "$right" | sort -V | tail -n 1)" = "$left" ]
}

base_version="$(read_version "$version_file")"
latest_version=""

if [ -n "$latest_override" ]; then
    if [ "$latest_override" != none ]; then
        latest_version="${latest_override#v}"
    fi
else
    latest_version="$({
        git tag --list 'v*' 2>/dev/null || true
    } | sed -n -E 's/^v((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))$/\1/p' | sort -V | tail -n 1)"
fi

if [ -z "$latest_version" ]; then
    printf '%s\n' "$base_version"
    exit 0
fi

[[ "$latest_version" =~ $semver_re ]] || {
    echo "Invalid latest release version: $latest_version" >&2
    exit 1
}

# A manually raised base version starts a new minor/major line unchanged.
# Otherwise every published release advances the latest stable patch number.
if version_gt "$base_version" "$latest_version"; then
    printf '%s\n' "$base_version"
    exit 0
fi

IFS=. read -r major minor patch <<< "$latest_version"
printf '%s.%s.%s\n' "$major" "$minor" "$((patch + 1))"
