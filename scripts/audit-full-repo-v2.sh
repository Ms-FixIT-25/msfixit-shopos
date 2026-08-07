#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
report="${AUDIT_REPORT:-full-code-audit-v2.txt}"
: > "$report"
errors=0
warnings=0
checked=0

section(){ printf '\n==== %s ====\n' "$1" | tee -a "$report"; }
error(){ errors=$((errors+1)); printf 'ERROR: %s\n' "$*" | tee -a "$report" >&2; }
warn(){ warnings=$((warnings+1)); printf 'WARN: %s\n' "$*" | tee -a "$report" >&2; }
run_error(){ local label="$1" tmp rc; shift; tmp="$(mktemp)"; set +e; "$@" >"$tmp" 2>&1; rc=$?; set -e; if [ "$rc" -ne 0 ]; then error "$label"; sed 's/^/    /' "$tmp" | tee -a "$report" >&2; fi; rm -f "$tmp"; }
run_warning(){ local label="$1" tmp rc; shift; tmp="$(mktemp)"; set +e; "$@" >"$tmp" 2>&1; rc=$?; set -e; if [ "$rc" -ne 0 ]; then warn "$label"; sed 's/^/    /' "$tmp" | tee -a "$report" >&2; fi; rm -f "$tmp"; }

section 'Repository inventory'
printf 'Commit: %s\n' "$(git rev-parse HEAD)" | tee -a "$report"
printf 'Tracked files: %s\n' "$(git ls-files | wc -l)" | tee -a "$report"
printf 'Shell .sh: %s\n' "$(git ls-files '*.sh' | wc -l)" | tee -a "$report"
printf 'Python .py: %s\n' "$(git ls-files '*.py' | wc -l)" | tee -a "$report"
printf 'PHP .php: %s\n' "$(git ls-files '*.php' | wc -l)" | tee -a "$report"
printf 'Workflows: %s\n' "$(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml' | wc -l)" | tee -a "$report"
printf 'systemd services: %s\n' "$(git ls-files 'image/package/etc/systemd/system/*.service' | wc -l)" | tee -a "$report"

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
merge_hits="$(git grep -nE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' -- '.github/workflows/*' 2>/dev/null || true)"
[ -z "$merge_hits" ] || { printf '%s\n' "$merge_hits" >> "$report"; error 'Active workflow contains gh pr merge'; }
write_all="$(git grep -nE '^[[:space:]]*permissions:[[:space:]]*write-all' -- '.github/workflows/*' 2>/dev/null || true)"
[ -z "$write_all" ] || { printf '%s\n' "$write_all" >> "$report"; error 'Workflow grants write-all'; }
sudo_all="$(git grep -nE 'NOPASSWD:[[:space:]]*ALL([[:space:]]|$)' -- 'image/package/etc/sudoers.d/*' 2>/dev/null || true)"
[ -z "$sudo_all" ] || { printf '%s\n' "$sudo_all" >> "$report"; error 'Unrestricted NOPASSWD:ALL in packaged sudoers'; }
sudo_wild="$(git grep -nE 'NOPASSWD:.*\*' -- 'image/package/etc/sudoers.d/*' 2>/dev/null || true)"
[ -z "$sudo_wild" ] || { printf '%s\n' "$sudo_wild" >> "$report"; warn 'Wildcard found in packaged NOPASSWD sudoers command; helper-side validation must remain strict'; }
world_write="$(git grep -nE 'chmod[[:space:]]+(-R[[:space:]]+)?0?777|chmod[[:space:]]+(-R[[:space:]]+)?a\+rwx' -- ':!tests/**' ':!docs/**' ':!scripts/audit-full-repo-v2.sh' 2>/dev/null || true)"
[ -z "$world_write" ] || { printf '%s\n' "$world_write" >> "$report"; error 'World-writable chmod found outside tests/docs'; }
pipe_shell="$(git grep -nE '(curl|wget)[^|;]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash)([[:space:]]|$)' -- ':!docs/**' ':!scripts/audit-full-repo-v2.sh' 2>/dev/null || true)"
[ -z "$pipe_shell" ] || { printf '%s\n' "$pipe_shell" >> "$report"; error 'Remote download piped directly into shell'; }

section 'Secret and execution heuristics'
secret_hits="$(git grep -nE -- '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}' -- ':!tests/**' ':!docs/**' ':!scripts/audit-full-repo-v2.sh' 2>/dev/null || true)"
[ -z "$secret_hits" ] || { printf '%s\n' "$secret_hits" >> "$report"; error 'High-confidence private key/token material found'; }
python_shell="$(git grep -nE 'shell[[:space:]]*=[[:space:]]*True|os\.system[[:space:]]*\(' -- '*.py' 2>/dev/null || true)"
[ -z "$python_shell" ] || { printf '%s\n' "$python_shell" >> "$report"; error 'Python shell execution primitive found'; }
php_process="$( { git grep -nE '(shell_exec|system|passthru|proc_open|popen|pcntl_exec)[[:space:]]*\(' -- '*.php' 2>/dev/null || true; git grep -nE '(^|[[:space:];{])exec[[:space:]]*\(' -- '*.php' 2>/dev/null || true; } | sort -u )"
[ -z "$php_process" ] || { printf '%s\n' "$php_process" >> "$report"; warn 'PHP OS-process execution primitive requires manual allowlist/shell-boundary review'; }
shell_eval="$(git grep -nE '^[[:space:]]*eval[[:space:]]+|[;&|][[:space:]]*eval[[:space:]]+' -- 'image/package/**' 'scripts/**' ':!scripts/audit-full-repo-v2.sh' 2>/dev/null || true)"
[ -z "$shell_eval" ] || { printf '%s\n' "$shell_eval" >> "$report"; warn 'Shell eval found in product/build code; manual trust-boundary review required'; }

section 'systemd package references'
while IFS= read -r unit; do
    [ -f "$unit" ] || continue; checked=$((checked+1))
    while IFS= read -r command; do
        command="${command#-}"; path="${command%% *}"
        case "$path" in /usr/local/bin/cloudflared) ;; /usr/local/*) [ -e "image/package${path}" ] || error "$unit references missing packaged executable $path";; esac
    done < <(sed -nE 's/^Exec(Start|StartPre|StartPost)=//p' "$unit")
    if grep -Eq '^Restart=always$' "$unit" && ! grep -Eq '^StartLimitIntervalSec=|^StartLimitBurst=' "$unit"; then warn "$unit restarts forever without explicit rate limit"; fi
    if grep -Eq '^Exec(Start|StartPre|StartPost)=.*(/bin/(ba)?sh|/usr/bin/(ba)?sh)[[:space:]]+-c' "$unit"; then warn "$unit launches shell -c from systemd; verify arguments cannot contain untrusted data"; fi
done < <(git ls-files 'image/package/etc/systemd/system/*.service')

section 'Regression wiring'
while IFS= read -r test_file; do
    [ -f "$test_file" ] || continue
    base="$(basename "$test_file")"
    refs="$(git grep -lF "$base" -- Makefile '.github/workflows/*' 'tests/*' 2>/dev/null | grep -Fxv "$test_file" || true)"
    [ -n "$refs" ] || warn "Regression test is not referenced by Makefile/workflows/another test: $test_file"
done < <(git ls-files 'tests/test-*.sh' 'tests/test-*.php')

section 'ShopOS cross-file contracts'
control=image/package/DEBIAN/control
firstboot=image/package/usr/local/sbin/msfixit-firstboot
firstlogin=image/package/usr/local/sbin/msfixit-first-login-init
health=image/package/usr/local/sbin/msfixit-health
office_init=image/package/usr/local/sbin/msfixit-office-init
cloud_service=image/package/etc/systemd/system/msfixit-cloudflared.service
cloud_runner=image/package/usr/local/sbin/msfixit-cloudflared-run
nginx=image/package/etc/nginx/sites-available/msfixit-shopos.conf
backup=image/package/usr/local/sbin/msfixit-backup
admin=image/package/usr/share/msfixit-shopos/admin-console/public/index.php
updates=image/package/usr/share/msfixit-shopos/admin-console/public/updates.php
build_workflow=.github/workflows/build-image.yml
app_runtime=image/package/usr/lib/msfixit-shopos/shopos-app-install.py
update_agent=image/package/usr/local/sbin/msfixit-update-agent
update_core=image/package/usr/local/sbin/msfixit-update
slot_writer=image/package/usr/local/sbin/msfixit-slot-writer

helper=image/package/usr/local/sbin/msfixit-app-install-helper
if [ -f "$helper" ]; then
  for runtime in shopos-app-install.py validate-shopos-app.py; do [ -f "image/package/usr/lib/msfixit-shopos/$runtime" ] || error "Packaged app runtime missing: /usr/lib/msfixit-shopos/$runtime"; done
fi

if [ -f "$nginx" ]; then
  generic="$(grep -nF 'location ~ \.php$ {' "$nginx" | head -n1 | cut -d: -f1 || true)"
  upload_deny="$(grep -nF 'location ~* /(?:uploads|files)/.*\.php$ {' "$nginx" | head -n1 | cut -d: -f1 || true)"
  hidden_deny="$(grep -nF 'location ~ /\. {' "$nginx" | head -n1 | cut -d: -f1 || true)"
  [ -z "$generic" ] && error 'Nginx generic PHP handler was not found'
  if [ -n "$generic" ] && { [ -z "$upload_deny" ] || [ "$generic" -lt "$upload_deny" ]; }; then error 'Nginx generic PHP handler precedes writable-upload PHP deny'; fi
  if [ -n "$generic" ] && { [ -z "$hidden_deny" ] || [ "$generic" -lt "$hidden_deny" ]; }; then error 'Nginx generic PHP handler precedes hidden-path deny; hidden .php can reach PHP-FPM'; fi
fi

if [ -f "$app_runtime" ]; then
  grep -Fq 'signed app_id does not match manifest id' "$app_runtime" || error 'Signed app_id is not bound to manifest id in packaged app installer'
  grep -Fq 'signed version does not match manifest version' "$app_runtime" || error 'Signed app version is not bound to manifest version in packaged app installer'
  grep -Fq 'unsupported archive member type' "$app_runtime" || error 'App installer does not reject non-file/non-directory tar member types'
  grep -Eq 'S_ISUID.*S_ISGID|S_ISGID.*S_ISUID' "$app_runtime" || error 'App installer does not reject setuid/setgid archive members'
fi

if [ -f "$firstboot" ] && [ -f "$firstlogin" ]; then
  if grep -Fq 'OS_ADMIN_PASSWORD' "$firstboot" || grep -Eq '(^|[[:space:]])chpasswd([[:space:]]|$)' "$firstboot"; then error 'Firstboot races interactive first-login for Linux administrator credentials'; fi
fi
if [ -f "$office_init" ] && grep -Fq 'msfixit-compliance-worker.timer' "$office_init" && ! grep -Fq 'msfixit-compliance-worker.timer' "$health"; then error 'Compliance worker timer is enabled but absent from health monitoring'; fi

if [ -f "$cloud_service" ]; then
  if grep -Eq 'ExecStart=.*--token[[:space:]]+\$\{?CF_TUNNEL_TOKEN|EnvironmentFile=.*cloudflared.*env' "$cloud_service"; then error 'Cloudflare tunnel secret reaches process environment/argv'; fi
  if grep -Fq 'msfixit-cloudflared-run' "$cloud_service"; then
      [ -f "$cloud_runner" ] || error 'Cloudflare service references missing token runner'
      grep -Fq -- '--token-file' "$cloud_runner" || error 'Cloudflare token runner does not use --token-file'
      grep -Fq 'chmod 0600 "$token_file"' "$cloud_runner" || error 'Cloudflare runtime token file is not forced to mode 0600'
  elif ! grep -Fq -- '--token-file' "$cloud_service"; then
      warn 'Cloudflare service has no visible --token-file path'
  fi
fi

if [ -f "$backup" ] && [ -f "$admin" ]; then
  archive_line="$(grep -E '^archive=' "$backup" | head -n1 || true)"
  case "$archive_line" in
    *.tar.zst*) grep -Fq 'shopos-*.tar.zst' "$admin" || error 'Admin dashboard backup glob does not match .tar.zst backup writer';;
    *.tar.gz*) grep -Fq 'shopos-*.tar.gz' "$admin" || error 'Admin dashboard backup glob does not match .tar.gz backup writer';;
    *) warn 'Could not determine outer backup archive extension';;
  esac
fi
if [ -f "$updates" ] && grep -Fq 'function helper(' "$updates" && grep -Fq '$timeout' "$updates" && ! grep -Eq 'proc_get_status|microtime|hrtime|stream_select' "$updates"; then warn 'Admin update helper accepts timeout without visible enforcement'; fi
if [ -f "$build_workflow" ] && grep -Fq 'gh release create' "$build_workflow"; then error 'Image build workflow can publish stable release before dedicated system release gate'; fi
if [ -f "$firstboot" ] && grep -Fq 'msfixit-shopos.local' "$firstboot" && ! grep -Eq '^Depends:.*(avahi-daemon|libnss-mdns)' "$control"; then warn '.local fallback advertised without explicit mDNS runtime dependency'; fi

if [ -f scripts/build-package.sh ] && grep -Fq 'BUILD_UTC=%s' scripts/build-package.sh && ! grep -Fq 'SOURCE_DATE_EPOCH' scripts/build-package.sh; then warn 'Build embeds wall-clock time without SOURCE_DATE_EPOCH support'; fi
if [ -f scripts/fetch-vendor-assets.sh ]; then
  grep -Eq 'woocommerce_(sha256|SHA256)|WOOCOMMERCE_SHA256' scripts/fetch-vendor-assets.sh scripts/build-package.sh || warn 'WooCommerce vendor artifact lacks pre-pinned SHA-256'
  grep -Eq 'redis_cache_(sha256|SHA256)|REDIS_CACHE_SHA256' scripts/fetch-vendor-assets.sh scripts/build-package.sh || warn 'Redis Object Cache vendor artifact lacks pre-pinned SHA-256'
  grep -Eq 'storefront_(sha256|SHA256)|STOREFRONT_SHA256' scripts/fetch-vendor-assets.sh scripts/build-package.sh || warn 'Storefront vendor artifact lacks pre-pinned SHA-256'
  if grep -Fq 'wordpress-${wordpress_version}-de_DE.zip.sha1' scripts/fetch-vendor-assets.sh && ! grep -Eq 'WORDPRESS_SHA(1|256)|wordpress_(sha1|sha256)' scripts/fetch-vendor-assets.sh scripts/build-package.sh; then warn 'WordPress integrity digest is fetched live rather than pinned in source'; fi
fi

if [ -f "$update_agent" ]; then
  grep -Fq 'exclusive_update_lock' "$update_agent" || error 'A/B update agent lacks an exclusive writer lock'
  writer_line="$(grep -nF "run([str(WRITER), 'write'" "$update_agent" | head -n1 | cut -d: -f1 || true)"
  stage_line="$(grep -nF "run([str(UPDATE), '--state', str(STATE), 'stage'" "$update_agent" | head -n1 | cut -d: -f1 || true)"
  if [ -z "$writer_line" ] || [ -z "$stage_line" ] || [ "$writer_line" -ge "$stage_line" ]; then error 'A/B update persistent stage is opened before inactive-slot write completes'; fi
fi
if [ -f "$update_core" ]; then
  grep -Fq 'fromisoformat' "$update_core" || error 'A/B update manifest timestamps are not parsed as real datetimes'
  grep -Fq 'MAX_CLOCK_SKEW' "$update_core" || error 'A/B update manifest has no bounded future clock-skew policy'
  grep -Fq 'manifest has expired' "$update_core" || error 'A/B update manifest expiry is not enforced'
  grep -Fq 'abort-stage' "$update_core" || error 'A/B update state machine lacks recoverable abort-stage cleanup'
fi
if [ -f "$slot_writer" ]; then
  grep -Fq 'BLKGETSIZE64' "$slot_writer" || error 'Slot writer does not determine block-device capacity before writing'
  grep -Fq 'ensure_capacity' "$slot_writer" || error 'Slot writer does not reject oversized rootfs before first write'
fi

section 'Summary'
printf 'Classified code/config targets inspected: %s\n' "$checked" | tee -a "$report"
printf 'Errors: %s\nWarnings: %s\n' "$errors" "$warnings" | tee -a "$report"
[ "$errors" -eq 0 ]
