#!/usr/bin/env bash
set -Eeuo pipefail

next_power_of_two() {
    local value="${1:?missing byte count}" target=1
    [[ "$value" =~ ^[0-9]+$ ]] || return 2
    (( value > 0 )) || return 2
    while (( target < value )); do
        target=$((target * 2))
    done
    printf '%s' "$target"
}

if [ "${1:-}" = '--self-test' ]; then
    test "$(next_power_of_two 1)" = 1
    test "$(next_power_of_two 1073741824)" = 1073741824
    test "$(next_power_of_two 37044092928)" = 68719476736

    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    truncate -s 37044092928 "$tmp"
    bash "$0" "$tmp" >/dev/null
    test "$(stat -c '%s' "$tmp")" = 68719476736
    test "$(du -B1 "$tmp" | awk '{print $1}')" -lt 1048576
    printf 'PASS: QEMU SD images grow sparsely to the next power-of-two size.\n'
    exit 0
fi

image="${1:?usage: normalize-qemu-sd-size.sh IMAGE}"
image="$(readlink -f "$image")"
test -f "$image"

original_size="$(stat -c '%s' "$image")"
target_size="$(next_power_of_two "$original_size")"

if (( target_size != original_size )); then
    truncate -s "$target_size" "$image"
fi

actual_size="$(stat -c '%s' "$image")"
test "$actual_size" = "$target_size"

printf 'QEMU SD image bytes: original=%s target=%s actual=%s sparse_growth=%s\n' \
    "$original_size" "$target_size" "$actual_size" \
    "$((target_size - original_size))"
