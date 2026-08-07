#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
report="${AUDIT_REPORT:-full-code-audit.txt}"
: > "$report"

errors=0
warnings=0
checked=0

section() {
    printf '\n==== %s ====\n' "$1" | tee -a "$report"
}

error() {
    errors=$((errors + 1))
    printf 'ERROR: %s\n' "$*" | tee -a "$report" >&2
}

warn() {
    warnings=$((warnings + 1))
    printf 'WARN: %s\n' "$*" | tee -a "$report" >&2
}

record_output() {
    local label="$1"
    shift
    local tmp rc
    tmp="$(mktemp)"
    set +e
    "$@" >"$tmp" 2>&1
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        error "$label"
        sed 's/^/    /' "$tmp" | tee -a "$report" >&2
    elif [ -s "$tmp" ]; then
        sed 's/^/    /' "$tmp" >> "$report"
    fi
    rm -f "$tmp"
}

section "Repository inventory"
printf 'Commit: %s\n' "$(git rev-parse HEAD)" | tee -a "$report"
printf 'Tracked files: %s\n' "$(git ls-files | wc -l)" | tee -a "$report"
printf 'Shell .sh: %s\n' "$(git ls-files '*.sh' | wc -l)" | tee -a "$report"
printf 'Python .py: %s\n' "$(git ls-files '*.py' | wc -l)" | tee -a "$report"
printf 'PHP .php: %s\n' "$(git ls-files '*.php' | wc -l)" | tee -a "$report"
printf 'Workflows: %s\n' "$(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml' | wc -l)" | tee -a "$report"
printf 'systemd units: %s\n' "$(git ls-files 'image/package/etc/systemd/system/*' | grep -Ec '\.(service|timer|path|socket|target)$' || true)" | tee -a "$report"

section "Shell syntax and ShellCheck"
mapfile -t shell_files < <(
    {
        git ls-files '*.sh'
        git ls-files 'image/package/DEBIAN/*' 'image/package/etc/update-motd.d/*' 'image/package/usr/local/bin/*' 'image/package/usr/local/sbin/*' 'scripts/*' 'tests/*'
    } | sort -u | while IFS= read -r f; do
        [ -f "$f" ] || continue
        first="$(head -n 1 "$f" 2>/dev/null || true)"
        case "$f:$first" in
            *.sh:*|*:*bash*|*:*/bin/sh*) printf '%s\n' "$f" ;;
        esac
    done
)
for f in "${shell_files[@]}"; do
    checked=$((checked + 1))
    first="$(head -n 1 "$f" 2>/dev/null || true)"
    if [[ "$first" == *'/bin/sh'* ]] && [[ "$first" != *bash* ]]; then
        record_output "POSIX shell syntax failed: $f" sh -n "$f"
    else
        record_output "Bash syntax failed: $f" bash -n "$f"
    fi
    if command -v shellcheck >/dev/null 2>&1; then
        tmp="$(mktemp)"
        set +e
        shellcheck -x -S warning "$f" >"$tmp" 2>&1
        rc=$?
        set -e
        if [ "$rc" -ne 0 ]; then
            error "ShellCheck warning-or-higher findings: $f"
            sed 's/^/    /' "$tmp" | tee -a "$report" >&2
        elif [ -s "$tmp" ]; then
            sed 's/^/    /' "$tmp" >> "$report"
        fi
        rm -f "$tmp"
    fi
done

section "Python syntax"
mapfile -t python_files < <(
    {
        git ls-files '*.py'
        git ls-files 'image/package/usr/local/bin/*' 'image/package/usr/local/sbin/*' 'scripts/*' 'tests/*'
    } | sort -u | while IFS= read -r f; do
        [ -f "$f" ] || continue
        first="$(head -n 1 "$f" 2>/dev/null || true)"
        case "$f:$first" in
            *.py:*|*:*python*) printf '%s\n' "$f" ;;
        esac
    done
)
for f in "${python_files[@]}"; do
    checked=$((checked + 1))
    record_output "Python compile failed: $f" python3 -m py_compile "$f"
done

section "PHP syntax"
mapfile -t php_files < <(
    {
        git ls-files '*.php'
        git ls-files 'image/package/usr/local/bin/*' 'image/package/usr/local/sbin/*' 'tests/*'
    } | sort -u | while IFS= read -r f; do
        [ -f "$f" ] || continue
        if [[ "$f" == *.php ]] || grep -Iq '^<?php' "$f" 2>/dev/null; then
            printf '%s\n' "$f"
        fi
    done
)
if command -v php >/dev/null 2>&1; then
    for f in "${php_files[@]}"; do
        checked=$((checked + 1))
        record_output "PHP lint failed: $f" php -l "$f"
    done
else
    warn 'php-cli unavailable; PHP syntax scan skipped'
fi

section "JSON and YAML syntax"
while IFS= read -r f; do
    [ -f "$f" ] || continue
    checked=$((checked + 1))
    record_output "Invalid JSON: $f" jq empty "$f"
done < <(git ls-files '*.json')

record_output "Invalid YAML document" ruby -e 'require "yaml"; ARGV.each { |f| YAML.parse_file(f) }' $(git ls-files '*.yml' '*.yaml')

section "GitHub Actions integrity"
if command -v actionlint >/dev/null 2>&1; then
    tmp="$(mktemp)"
    set +e
    actionlint -shellcheck= >"$tmp" 2>&1
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        error 'actionlint found workflow structure/expression errors'
        sed 's/^/    /' "$tmp" | tee -a "$report" >&2
    fi
    rm -f "$tmp"
fi

if git grep -nE 'gh[[:space:]]+pr[[:space:]]+merge|enablePullRequestAutoMerge|--auto([[:space:]]|$)' -- '.github/workflows/*' >> "$report" 2>/dev/null; then
    error 'An active workflow contains merge/auto-merge automation'
fi
if git grep -nE '^on:[[:space:]]*pull_request_target|^[[:space:]]+pull_request_target:' -- '.github/workflows/*' >> "$report" 2>/dev/null; then
    warn 'pull_request_target is present; review trust boundary carefully'
fi
if git grep -nE '^[[:space:]]*permissions:[[:space:]]*write-all' -- '.github/workflows/*' >> "$report" 2>/dev/null; then
    error 'A workflow grants write-all permissions'
fi

section "High-risk code patterns"
if git grep -nE 'chmod[[:space:]]+(-R[[:space:]]+)?0?777|chmod[[:space:]]+(-R[[:space:]]+)?a\+rwx' -- ':!tests/**' ':!docs/**' >> "$report" 2>/dev/null; then
    error 'World-writable chmod found outside tests/docs'
fi
if git grep -nE 'NOPASSWD:[[:space:]]*ALL([[:space:]]|$)' -- ':!tests/**' ':!docs/**' >> "$report" 2>/dev/null; then
    error 'Unrestricted NOPASSWD:ALL found'
fi
if git grep -nE '(curl|wget)[^|;]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash)([[:space:]]|$)' -- ':!docs/**' >> "$report" 2>/dev/null; then
    error 'Remote download piped directly to a shell'
fi
if git grep -nE '(^|[^[:alnum:]_])(eval|source)[[:space:]]+["'"']?\$' -- ':!tests/**' ':!docs/**' >> "$report" 2>/dev/null; then
    warn 'Dynamic eval/source found; manual review required'
fi
if git grep -nE '\b(shell_exec|passthru|pcntl_exec)[[:space:]]*\(' -- '*.php' >> "$report" 2>/dev/null; then
    error 'Dangerous PHP process-execution primitive found'
fi
if git grep -nE '\bunserialize[[:space:]]*\(' -- '*.php' >> "$report" 2>/dev/null; then
    warn 'PHP unserialize found; verify trusted input only'
fi
if git grep -nE 'shell[[:space:]]*=[[:space:]]*True|os\.system[[:space:]]*\(' -- '*.py' >> "$report" 2>/dev/null; then
    error 'Python shell execution primitive found'
fi

section "Secret material heuristics"
if git grep -nE '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}' -- ':!tests/**' ':!docs/**' >> "$report" 2>/dev/null; then
    error 'High-confidence private key/token pattern found'
fi

section "systemd unit review"
while IFS= read -r unit; do
    [ -f "$unit" ] || continue
    checked=$((checked + 1))
    if grep -Eq '^User=root$' "$unit" && ! grep -Eq '^ProtectSystem=|^NoNewPrivileges=' "$unit"; then
        warn "$unit runs explicitly as root without visible sandbox directives"
    fi
    if grep -Eq '^Restart=always$' "$unit" && ! grep -Eq '^StartLimitIntervalSec=|^StartLimitBurst=' "$unit"; then
        warn "$unit uses Restart=always without an explicit start-rate limit"
    fi
    if grep -Eq '^ExecStartPre=.*(read|first-login|wizard|setup)' "$unit"; then
        warn "$unit has an interactive/setup-looking ExecStartPre; verify it cannot block service startup"
    fi
done < <(git ls-files 'image/package/etc/systemd/system/*.service')

section "File permission and package-contract review"
if [ -f image/package/DEBIAN/control ]; then
    if grep -Eq '^Depends:.*curl' image/package/DEBIAN/control && ! grep -Eq '^Depends:.*ca-certificates' image/package/DEBIAN/control; then
        error 'curl is packaged without ca-certificates dependency'
    fi
fi

section "Summary"
printf 'Files/check targets inspected: %s\n' "$checked" | tee -a "$report"
printf 'Errors: %s\nWarnings: %s\n' "$errors" "$warnings" | tee -a "$report"

if [ "$errors" -ne 0 ]; then
    exit 1
fi
