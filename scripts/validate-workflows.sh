#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

mapfile -t workflows < <(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print | sort)
if (( ${#workflows[@]} == 0 )); then
    echo 'No GitHub Actions workflows found.' >&2
    exit 1
fi

ruby -e '
require "yaml"
ARGV.each do |file|
  YAML.parse_file(file)
  puts "PASS YAML: #{file}"
end
' "${workflows[@]}"

if command -v actionlint >/dev/null 2>&1; then
    # SC2317 is a ShellCheck false positive for trap-invoked helper functions.
    # All actual syntax, runner-label and GitHub Actions errors remain fatal.
    actionlint -color -ignore 'SC2317:'
else
    echo 'actionlint is required for GitHub Actions semantic validation.' >&2
    exit 1
fi

# Regression guard for the exact failure that invalidated multiple workflows:
# content belonging to a run: | block must never escape to column one.
if grep -nE '^(SHOP_URL|SHOP_TITLE|SHOP_ADMIN_|OS_ADMIN_|WORDPRESS_|#!/usr/bin/env bash|\[Unit\]|\[Service\]|\[Install\])' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null; then
    echo 'Detected unindented heredoc content at YAML column one.' >&2
    exit 1
fi

printf 'PASS: all GitHub Actions workflows are valid YAML and pass actionlint.\n'
