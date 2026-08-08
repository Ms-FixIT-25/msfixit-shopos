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

# Production gates are fail-closed. A Draft PR may remain unmergeable, but its
# required release jobs must still execute. Conditional helper steps (for
# example a cache miss) are allowed; top-level release jobs are not skippable.
ruby - <<'RUBY'
require 'yaml'

release_path = '.github/workflows/shopos-release-gate.yml'
release = YAML.load_file(release_path)
jobs = release.fetch('jobs')

jobs.each do |job_name, job|
  if job.is_a?(Hash) && job.key?('if')
    abort("Required release job #{job_name.inspect} must not have a job-level if condition")
  end
end

raw = File.read(release_path)
abort('Draft PRs must not skip the release gate') if raw.include?('pull_request.draft')
abort('Release gate must run when a PR is converted back to Draft') unless raw.include?('converted_to_draft')
abort('Release evidence must fail when files are missing') if raw.match?(/if-no-files-found:\s*warn/)

Dir['.github/workflows/*.{yml,yaml}'].sort.each do |path|
  text = File.read(path)
  if text.match?(/^\s*continue-on-error:\s*true\s*$/)
    abort("#{path}: continue-on-error: true is forbidden for ShopOS workflows")
  end
end

puts 'PASS: required ShopOS release jobs are fail-closed and cannot be skipped for Draft state.'
RUBY

printf 'PASS: all GitHub Actions workflows are valid YAML, pass actionlint and enforce fail-closed release gates.\n'
