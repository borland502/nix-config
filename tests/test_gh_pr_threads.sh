#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$repo_root/tests/helpers/testlib.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/fixture.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
  {"isResolved":false,"isOutdated":false,"path":"src/a.ts","line":12,"comments":{"nodes":[{"author":{"login":"alice"},"body":"Please fix","url":"https://example.invalid/a"}]}},
  {"isResolved":true,"isOutdated":false,"path":"src/b.ts","line":4,"comments":{"nodes":[{"author":{"login":"bob"},"body":"Done","url":"https://example.invalid/b"}]}}
]}}}}}
JSON

cat >"$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
if [[ "$1 $2 $3" == "pr view 42" ]]; then
	printf '{"number":42,"url":"https://github.com/owner/repo/pull/42"}\n'
	exit 0
fi
exit 64
SH

cat >"$tmp/bin/gh-graphql" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$TRACE_FILE"
jq_file=""
while [[ $# -gt 0 ]]; do
	if [[ "$1" == "--jq" ]]; then jq_file="$2"; shift 2; else shift; fi
done
jq -f "$jq_file" "$FIXTURE_FILE"
SH
chmod +x "$tmp/bin/gh" "$tmp/bin/gh-graphql"

helper="$repo_root/chezmoi/dot_local/bin/executable_gh-pr-threads"
data_dir="$repo_root/chezmoi/dot_local/share/gh-pr-threads"
output="$(PATH="$tmp/bin:$PATH" TRACE_FILE="$tmp/trace" FIXTURE_FILE="$tmp/fixture.json" GH_PR_THREADS_DATA_DIR="$data_dir" "$helper" 42 --author alice)"
assert_contains "$output" 'src/a.ts:12'
assert_contains "$output" 'alice'
assert_not_contains "$output" 'src/b.ts'
assert_file_contains "$tmp/trace" 'review-threads.graphql'
assert_file_contains "$tmp/trace" 'review-threads.jq'
assert_file_contains "$tmp/trace" 'owner=owner'
assert_file_contains "$tmp/trace" 'repo=repo'
assert_file_contains "$tmp/trace" 'number=42'

json_output="$(PATH="$tmp/bin:$PATH" TRACE_FILE="$tmp/trace" FIXTURE_FILE="$tmp/fixture.json" GH_PR_THREADS_DATA_DIR="$data_dir" "$helper" 42 --all --json)"
[[ "$(jq length <<<"$json_output")" -eq 2 ]]
