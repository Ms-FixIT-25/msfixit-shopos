#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
report="${AUDIT_REPORT:-full-code-audit.txt}"
: > "$report"
errors=0
warnings=0
checked=0

section(){ printf '\n==== %s ====\n' "$1" | tee -a "$report"; }
error(){ errors=$((errors+1)); printf 'ERROR: %s\n' "$*" | tee -a "$report" >&2; }
warn(){ warnings=$((warnings+1)); printf 'WARN: %s\n' "$*" | tee -a "$report" >&2; }

run_error(){
    local label="$1" tmp rc; shift; tmp="$(mktemp)"
    set +e; "$@" >"$tmp" 2>&1; rc=$?; set -e
    if [ "$rc" -ne 0 ]; then error "$label"; sed 's/^/    /' "$tmp" | tee -a "$report" >&2; fi
    rm -f "$tmp"
}
run_warning(){
    local label="$1" tmp rc; shift; tmp="$(mktemp)"
    set +e; "$@" >"$tmp" 2>&1; rc=$?; set -e
    if [ "$rc" -ne 0 ]; then warn "$label"; sed 's/^/    /' "$tmp" | tee -a "$report" >&2; fi
    rm -f "$tmp"
}

section 'Repository inventory'
printf 'Commit: %s\n' "$(git rev-parse HEAD)" | tee -a "$report"
printf 'Tracked files: %s\n' "$(git ls-files | wc -l)" | tee -a "$report"
printf 'Shell .sh: %s\n' "$(git ls-files '*.sh' | wc -l)" | tee -a "$report"
printf 'Python .py: %s\n' "$(git ls-files '*.py' | wc -l)" | tee -a "$report"
printf 'PHP .php: %s\n' "$(git ls-files '*.php' | wc -l)" | tee -a "$report"
printf 'Workflows: %s\n' "$(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml' | wc -l)" | tee -a "$report"

section 'Syntax and static analysis'
mapfile -t shell_files < <(
  { git ls-files '*.sh'; git ls-files 'image/package/DEBIAN/*' 'image/package/etc/update-motd.d/*' 'image/package/usr/local/bin/*' 'image/package/usr/local/sbin/*' 'scripts/*' 'tests/*'; } \
  | sort -u | while IFS= read -r f; do
      [ -f "$f" ] || continue
      first="$(head -n1 "$f" 2>/dev/null || true)"
      case "$f:$first" in *.sh:*|*:*bash*|*:*/bin/sh*) printf '%s\n' "$f";; esac
    done
)
for f in "${shell_files[@]}"; do
    checked=$((checked+1)); first="$(head -n1 "$f" 2>/dev/null || true)"
    if [[ "$first" == *'/bin/sh'* && "$first" != *bash* ]]; then run_error "POSIX shell syntax: $f" sh -n "$f"; else run_error "Bash syntax: $f" bash -n "$f"; fi
    command -v shellcheck >/dev/null 2>&1 && run_warning "ShellCheck warning-or-higher: $f" shellcheck -x -S warning "$f"
done

mapfile -t py_files < <({ git ls-files '*.py'; git ls-files 'image/package/usr/local/bin/*' 'image/package/usr/local/sbin/*' 'scripts/*'; } | sort -u | while IFS= read -r f; do [ -f "$f" ] || continue; first="$(head -n1 "$f" 2>/dev/null || true)"; case "$f:$first" in *.py:*|*:*python*) printf '%s\n' "$f";; esac; done)
for f in "${py_files[@]}"; do checked=$((checked+1)); run_error "Python compile: $f" python3 -m py_compile "$f"; done

mapfile -t php_files < <(git ls-files '*.php')
if command -v php >/dev/null 2>&1; then for f in "${php_files[@]}"; do checked=$((checked+1)); run_error "PHP lint: $f" php -l "$f"; done; else warn 'php-cli unavailable'; fi

while IFS= read -r f; do [ -f "$f" ] || continue; checked=$((checked+1)); run_error "Invalid JSON: $f" jq empty "$f"; done < <(git ls-files '*.json')
mapfile -t yaml_files < <(git ls-files '*.yml' '*.yaml')
if (( ${#yaml_files[@]} )); then run_error 'Invalid YAML' ruby -e 'require "yaml"; ARGV.each{|f| YAML.parse_file(f)}' "${yaml_files[@]}"; fi
command -v actionlint >/dev/null 2>&1 && run_error 'actionlint workflow error' actionlint -shellcheck=

section 'CI and privilege boundaries'
# Match only an actual shell command, not regression tests containing the text.
merge_hits="$(git grep -nE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' -- '.github/workflows/*' 2>/dev/null || true)"
[ -z "$merge_hits" ] || { printf '%s\n' "$merge_hits" >> "$report"; error 'Active workflow contains gh pr merge'; }
write_all="$(git grep -nE '^[[:space:]]*permissions:[[:space:]]*write-all' -- '.github/workflows/*' 2>/dev/null || true)"
[ -z "$write_all" ] || { printf '%s\n' "$write_all" >> "$report"; error 'Workflow grants write-all'; }
sudo_all="$(git grep -nE 'NOPASSWD:[[:space:]]*ALL([[:space:]]|$)' -- 'image/package/etc/sudoers.d/*' 2>/dev/null || true)"
[ -z "$sudo_all" ] || { printf '%s\n' "$sudo_all" >> "$report"; error 'Unrestricted NOPASSWD:ALL in packaged sudoers'; }
pipe_shell="$(git grep -nE '(curl|wget)[^|;]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash)([[:space:]]|$)' -- ':!docs/**' ':!scripts/audit-full-repo.sh' 2>/dev/null || true)"
[ -z "$pipe_shell" ] || { printf '%s\n' "$pipe_shell" >> "$report"; error 'Remote download piped directly into shell'; }

section 'Secret and execution heuristics'
secret_hits="$(git grep -nE -- '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}' -- ':!tests/**' ':!docs/**' ':!scripts/audit-full-repo.sh' 2>/dev/null || true)"
[ -z "$secret_hits" ] || { printf '%s\n' "$secret_hits" >> "$report"; error 'High-confidence private key/token material found'; }
python_shell="$(git grep -nE 'shell[[:space:]]*=[[:space:]]*True|os\.system[[:space:]]*\(' -- '*.py' 2>/dev/null || true)"
[ -z "$python_shell" ] || { printf '%s\n' "$python_shell" >> "$report"; error 'Python shell execution primitive found'; }
php_exec="$(git grep -nE '(shell_exec|passthru|pcntl_exec)[[:space:]]*\(' -- '*.php' 2>/dev/null || true)"
[ -z "$php_exec" ] || { printf '%s\n' "$php_exec" >> "$report"; warn 'PHP process execution requires manual trust-boundary review'; }

section 'systemd package references'
while IFS= read -r unit; do
    [ -f "$unit" ] || continue; checked=$((checked+1))
    while IFS= read -r command; do
        command="${command#-}"; path="${command%% *}"
        case "$path" in
          /usr/local/bin/cloudflared) ;;
          /usr/local/*)
              packaged="image/package${path}"
              [ -e "$packaged" ] || error "$unit references missing packaged executable $path"
              ;;
        esac
    done < <(sed -nE 's/^Exec(Start|StartPre|StartPost)=//p' "$unit")
    if grep -Eq '^Restart=always$' "$unit" && ! grep -Eq '^StartLimitIntervalSec=|^StartLimitBurst=' "$unit"; then warn "$unit restarts forever without explicit rate limit"; fi
done < <(git ls-files 'image/package/etc/systemd/system/*.service')

section 'ShopOS cross-file contracts'
control=image/package/DEBIAN/control
firstboot=image/package/usr/local/sbin/msfixit-firstboot
firstlogin=image/package/usr/local/sbin/msfixit-first-login-init
health=image/package/usr/local/sbin/msfixit-health
office_init=image/package/usr/local/sbin/msfixit-office-init
cloud_service=image/package/etc/systemd/system/msfixit-cloudflared.service
nginx=image/package/etc/nginx/sites-available/msfixit-shopos.conf
backup=image/package/usr/local/sbin/msfixit-backup
admin=image/package/usr/share/msfixit-shopos/admin-console/public/index.php
updates=image/package/usr/share/msfixit-shopos/admin-console/public/updates.php
build_workflow=.github/workflows/build-image.yml

helper=image/package/usr/local/sbin/msfixit-app-install-helper
if [ -f "$helper" ]; then
  for runtime in shopos-app-install.py validate-shopos-app.py; do
    [ -f "image/package/usr/lib/msfixit-shopos/$runtime" ] || error "Packaged app runtime missing: /usr/lib/msfixit-shopos/$runtime"
  done
fi

if [ -f "$nginx" ]; then
  generic="$(grep -nF 'location ~ \.php$ {' "$nginx" | head -n1 | cut -d: -f1 || true)"
  deny="$(grep -nF 'location ~* /(?:uploads|files)/.*\.php$ {' "$nginx" | head -n1 | cut -d: -f1 || true)"
  if [ -n "$generic" ] && [ -n "$deny" ] && [ "$generic" -lt "$deny" ]; then error 'Nginx generic PHP handler precedes writable-upload PHP deny'; fi
fi

if [ -f "$firstboot" ] && [ -f "$firstlogin" ]; then
  if grep -Fq 'OS_ADMIN_PASSWORD' "$firstboot" || grep -Eq '(^|[[:space:]])chpasswd([[:space:]]|$)' "$firstboot"; then error 'Firstboot races interactive first-login for Linux administrator credentials'; fi
fi

if [ -f "$office_init" ] && grep -Fq 'msfixit-compliance-worker.timer' "$office_init" && ! grep -Fq 'msfixit-compliance-worker.timer' "$health"; then
  error 'Compliance worker timer is enabled but absent from health monitoring'
fi

if [ -f "$cloud_service" ] && grep -Eq 'ExecStart=.*--token[[:space:]]+\$\{?CF_TUNNEL_TOKEN' "$cloud_service"; then
  error 'Cloudflare tunnel token is exposed in process arguments'
fi

if [ -f "$backup" ] && [ -f "$admin" ] && grep -Fq 'shopos-${stamp}.tar.gz' "$backup" && grep -Fq 'shopos-*.tar.zst' "$admin"; then
  warn 'Admin dashboard backup glob does not match backup writer extension'
fi

if [ -f "$updates" ] && grep -Fq 'function helper(array $args,int $timeout=' "$updates" && ! grep -Eq 'stream_select|proc_get_status|hrtime|microtime.*timeout' "$updates"; then
  warn 'Admin update helper accepts a timeout but does not enforce it'
fi

if [ -f "$build_workflow" ] && grep -Fq 'gh release create' "$build_workflow"; then
  error 'Image build workflow can publish a stable GitHub Release before the full system release gate'
fi

if [ -f "$firstboot" ] && grep -Fq 'msfixit-shopos.local' "$firstboot" && ! grep -Eq '^Depends:.*(avahi-daemon|libnss-mdns)' "$control"; then
  warn '.local fallback is advertised without an explicit mDNS runtime dependency'
fi

if grep -Fq 'BUILD_UTC=%s' scripts/build-package.sh; then warn 'Build embeds wall-clock time and is not byte-reproducible without SOURCE_DATE_EPOCH'; fi
if grep -Fq 'downloads.wordpress.org/plugin/woocommerce' scripts/fetch-vendor-assets.sh && ! grep -Eq 'woocommerce_(sha256|SHA256)|WOOCOMMERCE_SHA256' scripts/fetch-vendor-assets.sh scripts/build-package.sh; then warn 'WooCommerce vendor artifact lacks a pre-pinned expected SHA-256'; fi

section 'Summary'
printf 'Classified code/config targets inspected: %s\n' "$checked" | tee -a "$report"
printf 'Errors: %s\nWarnings: %s\n' "$errors" "$warnings" | tee -a "$report"
[ "$errors" -eq 0 ]
