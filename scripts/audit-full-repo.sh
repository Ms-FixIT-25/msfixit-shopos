#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
report="${AUDIT_REPORT:-full-code-audit.txt}"
: > "$report"

errors=0
warnings=0
checked=0

section() { printf '\n==== %s ====\n' "$1" | tee -a "$report"; }
error() { errors=$((errors + 1)); printf 'ERROR: %s\n' "$*" | tee -a "$report" >&2; }
warn() { warnings=$((warnings + 1)); printf 'WARN: %s\n' "$*" | tee -a "$report" >&2; }

record_output() {
    local label="$1" tmp rc
    shift
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

record_warning_output() {
    local label="$1" tmp rc
    shift
    tmp="$(mktemp)"
    set +e
    "$@" >"$tmp" 2>&1
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        warn "$label"
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
printf 'systemd unit files: %s\n' "$(git ls-files 'image/package/etc/systemd/system/*' | wc -l)" | tee -a "$report"

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
        record_output "ShellCheck error-level finding: $f" shellcheck -x -S error "$f"
        # Warning-level findings are valuable audit input but should not turn
        # style-only diagnostics such as SC1090/SC2034 into product failures.
        record_warning_output "ShellCheck warning-level finding: $f" shellcheck -x -S warning "$f"
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
        git ls-files 'image/package/usr/local/bin/*' 'image/package/usr/local/sbin/*'
    } | sort -u | while IFS= read -r f; do
        [ -f "$f" ] || continue
        if [[ "$f" == *.php ]] || head -c 16 "$f" 2>/dev/null | grep -Fq '<?php'; then
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

mapfile -t yaml_files < <(git ls-files '*.yml' '*.yaml')
if (( ${#yaml_files[@]} > 0 )); then
    record_output "Invalid YAML document" ruby -e 'require "yaml"; ARGV.each { |f| YAML.parse_file(f) }' "${yaml_files[@]}"
fi

section "GitHub Actions integrity"
if command -v actionlint >/dev/null 2>&1; then
    record_output 'actionlint found workflow structure/expression errors' actionlint -shellcheck=
fi

merge_hits="$(git grep -nE 'gh[[:space:]]+pr[[:space:]]+merge|enablePullRequestAutoMerge|--auto([[:space:]]|$)' -- '.github/workflows/*' 2>/dev/null || true)"
if [ -n "$merge_hits" ]; then
    printf '%s\n' "$merge_hits" >> "$report"
    error 'An active workflow contains merge/auto-merge automation'
fi

pr_target_hits="$(git grep -nE '^on:[[:space:]]*pull_request_target|^[[:space:]]+pull_request_target:' -- '.github/workflows/*' 2>/dev/null || true)"
if [ -n "$pr_target_hits" ]; then
    printf '%s\n' "$pr_target_hits" >> "$report"
    warn 'pull_request_target is present; review trust boundary carefully'
fi

write_all_hits="$(git grep -nE '^[[:space:]]*permissions:[[:space:]]*write-all' -- '.github/workflows/*' 2>/dev/null || true)"
if [ -n "$write_all_hits" ]; then
    printf '%s\n' "$write_all_hits" >> "$report"
    error 'A workflow grants write-all permissions'
fi

section "High-risk code patterns"
world_hits="$(git grep -nE 'chmod[[:space:]]+(-R[[:space:]]+)?0?777|chmod[[:space:]]+(-R[[:space:]]+)?a\+rwx' -- ':!tests/**' ':!docs/**' 2>/dev/null || true)"
if [ -n "$world_hits" ]; then printf '%s\n' "$world_hits" >> "$report"; error 'World-writable chmod found outside tests/docs'; fi

sudo_hits="$(git grep -nE 'NOPASSWD:[[:space:]]*ALL([[:space:]]|$)' -- ':!tests/**' ':!docs/**' 2>/dev/null || true)"
if [ -n "$sudo_hits" ]; then printf '%s\n' "$sudo_hits" >> "$report"; error 'Unrestricted NOPASSWD:ALL found'; fi

pipe_hits="$(git grep -nE '(curl|wget)[^|;]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash)([[:space:]]|$)' -- ':!docs/**' 2>/dev/null || true)"
if [ -n "$pipe_hits" ]; then printf '%s\n' "$pipe_hits" >> "$report"; error 'Remote download piped directly to a shell'; fi

dynamic_source_hits="$(git grep -nE '(eval|source)[[:space:]]+.*\$' -- ':!tests/**' ':!docs/**' 2>/dev/null || true)"
if [ -n "$dynamic_source_hits" ]; then printf '%s\n' "$dynamic_source_hits" >> "$report"; warn 'Dynamic eval/source found; manual review required'; fi

php_exec_hits="$(git grep -nE '(shell_exec|passthru|pcntl_exec)[[:space:]]*\(' -- '*.php' 2>/dev/null || true)"
if [ -n "$php_exec_hits" ]; then printf '%s\n' "$php_exec_hits" >> "$report"; warn 'PHP process-execution primitive found; verify strict allowlists and shell escaping'; fi

unserialize_hits="$(git grep -nE 'unserialize[[:space:]]*\(' -- '*.php' 2>/dev/null || true)"
if [ -n "$unserialize_hits" ]; then printf '%s\n' "$unserialize_hits" >> "$report"; warn 'PHP unserialize found; verify trusted input only'; fi

python_shell_hits="$(git grep -nE 'shell[[:space:]]*=[[:space:]]*True|os\.system[[:space:]]*\(' -- '*.py' 2>/dev/null || true)"
if [ -n "$python_shell_hits" ]; then printf '%s\n' "$python_shell_hits" >> "$report"; error 'Python shell execution primitive found'; fi

section "Secret material heuristics"
secret_hits="$(git grep -nE -- '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}' -- ':!tests/**' ':!docs/**' 2>/dev/null || true)"
if [ -n "$secret_hits" ]; then printf '%s\n' "$secret_hits" >> "$report"; error 'High-confidence private key/token pattern found'; fi

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

section "ShopOS cross-file contracts"
control=image/package/DEBIAN/control
if [ -f "$control" ]; then
    if grep -Eq '^Depends:.*curl' "$control" && ! grep -Eq '^Depends:.*ca-certificates' "$control"; then
        error 'curl is packaged without ca-certificates dependency'
    fi
fi

# The privileged app helper must not point at runtime files that never enter the
# Debian package. This catches source-tree-only installer scripts.
helper=image/package/usr/local/sbin/msfixit-app-install-helper
if [ -f "$helper" ]; then
    for runtime in shopos-app-install.py validate-shopos-app.py; do
        if grep -Fq "$runtime" "$helper" scripts/shopos-app-install.py 2>/dev/null \
            && [ ! -f "image/package/usr/lib/msfixit-shopos/$runtime" ]; then
            error "Packaged app runtime is missing image/package/usr/lib/msfixit-shopos/$runtime"
        fi
    done
fi

# Generic PHP handling must never precede the explicit uploads/files PHP deny.
nginx=image/package/etc/nginx/sites-available/msfixit-shopos.conf
if [ -f "$nginx" ]; then
    generic_line="$(grep -nE 'location[[:space:]]+~[[:space:]]+.*\\\.php' "$nginx" | head -n1 | cut -d: -f1 || true)"
    deny_line="$(grep -nE 'location[[:space:]]+~\*.*uploads.*\\\.php' "$nginx" | head -n1 | cut -d: -f1 || true)"
    if [ -n "$generic_line" ] && [ -n "$deny_line" ] && [ "$generic_line" -lt "$deny_line" ]; then
        error 'Nginx generic PHP handler appears before upload-PHP deny rule'
    fi
fi

backup=image/package/usr/local/sbin/msfixit-backup
admin=image/package/usr/share/msfixit-shopos/admin-console/public/index.php
if [ -f "$backup" ] && [ -f "$admin" ]; then
    if grep -Fq 'shopos-${stamp}.tar.gz' "$backup" && grep -Fq "shopos-*.tar.zst" "$admin"; then
        warn 'Admin dashboard searches for .tar.zst backups while backup service writes .tar.gz'
    fi
fi

section "Summary"
printf 'Files/check targets inspected: %s\n' "$checked" | tee -a "$report"
printf 'Errors: %s\nWarnings: %s\n' "$errors" "$warnings" | tee -a "$report"

if [ "$errors" -ne 0 ]; then
    exit 1
fi
