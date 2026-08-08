#!/usr/bin/env bash
# Shared ShopOS test assertions.
# Goal: inspect executable/configuration semantics without failing on prose-only comments.

shopos_test_debug=${SHOPOS_TEST_DEBUG:-0}

shopos_debug() {
    [ "$shopos_test_debug" = "1" ] || return 0
    printf 'DEBUG: %s\n' "$*"
}

shopos_warn() {
    local message="$1"
    printf '::warning::%s\n' "$message"
}

shopos_error() {
    local message="$1"
    printf '::error::%s\n' "$message"
}

# Print non-empty, non-comment-only lines with original line numbers.
# This deliberately ignores documentation comments while preserving inline syntax.
shopos_code_lines() {
    local file="$1"
    awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        { printf "%d:%s\n", NR, $0 }
    ' "$file"
}

shopos_show_matches() {
    local matches="$1"
    [ -n "$matches" ] || return 0
    printf '%s\n' "$matches" | sed 's/^/DEBUG MATCH: /'
}

assert_code_not_contains_literal() {
    local file="$1" literal="$2" message="$3"
    local matches
    matches="$(shopos_code_lines "$file" | grep -F -- "$literal" || true)"
    if [ -n "$matches" ]; then
        shopos_error "$message"
        shopos_show_matches "$matches"
        return 1
    fi
    shopos_debug "PASS no code literal '$literal' in $file"
}

assert_code_not_matches() {
    local file="$1" regex="$2" message="$3"
    local matches
    matches="$(shopos_code_lines "$file" | grep -E -- "$regex" || true)"
    if [ -n "$matches" ]; then
        shopos_error "$message"
        shopos_show_matches "$matches"
        return 1
    fi
    shopos_debug "PASS no code regex '$regex' in $file"
}

assert_code_contains_literal() {
    local file="$1" literal="$2" message="$3"
    local matches
    matches="$(shopos_code_lines "$file" | grep -F -- "$literal" || true)"
    if [ -z "$matches" ]; then
        shopos_error "$message"
        printf 'DEBUG EXPECTED: %s in %s\n' "$literal" "$file"
        return 1
    fi
    shopos_debug "PASS code literal '$literal' in $file"
}

assert_code_matches() {
    local file="$1" regex="$2" message="$3"
    local matches
    matches="$(shopos_code_lines "$file" | grep -E -- "$regex" || true)"
    if [ -z "$matches" ]; then
        shopos_error "$message"
        printf 'DEBUG EXPECTED REGEX: %s in %s\n' "$regex" "$file"
        return 1
    fi
    shopos_debug "PASS code regex '$regex' in $file"
}

warn_code_contains_literal() {
    local file="$1" literal="$2" message="$3"
    local matches
    matches="$(shopos_code_lines "$file" | grep -F -- "$literal" || true)"
    if [ -n "$matches" ]; then
        shopos_warn "$message"
        shopos_show_matches "$matches"
    fi
}

warn_code_matches() {
    local file="$1" regex="$2" message="$3"
    local matches
    matches="$(shopos_code_lines "$file" | grep -E -- "$regex" || true)"
    if [ -n "$matches" ]; then
        shopos_warn "$message"
        shopos_show_matches "$matches"
    fi
}
