#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/test-assertions.sh
source "$root/tests/lib/test-assertions.sh"

helper="$root/tests/lib/test-assertions.sh"
bash -n "$helper"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/comment-only.sh" <<'EOF'
#!/usr/bin/env bash
# xterm appears only in documentation and must be ignored.
   # /usr/bin/xterm --this-is-not-code
printf '%s\n' ok
EOF

cat >"$tmp/real-code.sh" <<'EOF'
#!/usr/bin/env bash
/usr/bin/xterm -e true
EOF

assert_code_not_contains_literal "$tmp/comment-only.sh" '/usr/bin/xterm' \
    'comment-only xterm text must not be treated as executable code'

if assert_code_not_contains_literal "$tmp/real-code.sh" '/usr/bin/xterm' \
    'self-test intentionally detects executable xterm'; then
    printf 'FAIL: comment-aware assertion failed to detect real executable code\n' >&2
    exit 1
fi

# Warning assertions must annotate but never fail the test process.
warn_code_contains_literal "$tmp/real-code.sh" '/usr/bin/xterm' \
    'SELFTEST: warning annotation path is working'

# Heuristic only: identify fragile broad negative greps. These are warnings so
# legacy tests can be migrated incrementally instead of breaking all CI at once.
while IFS= read -r test_file; do
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        case "$hit" in
            *test-test-harness-quality.sh*) continue ;;
        esac
        printf '::warning file=%s::Potential comment-sensitive grep; prefer tests/lib/test-assertions.sh or a syntax-anchored pattern. %s\n' \
            "${test_file#$root/}" "$hit"
    done < <(
        grep -nE "if[[:space:]]+!?[[:space:]]*grep[[:space:]]+-[A-Za-z]*q[[:space:]]+['\"][A-Za-z0-9_.:/-]+['\"]" \
            "$test_file" 2>/dev/null || true
    )
done < <(find "$root/tests" -maxdepth 1 -type f -name '*.sh' | sort)

printf 'PASS: ShopOS test harness ignores comment-only matches, detects real code, emits non-fatal warnings, and audits fragile grep patterns.\n'
