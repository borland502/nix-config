#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$repo_root/tests/helpers/testlib.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home/.cache/copilot/2026-09-01-pr-review/node_modules" \
	"$tmp/home/.config/copilot/session-state/recent" \
	"$tmp/home/.config/copilot/session-state/retained-session"

cat >"$tmp/home/.cache/copilot/session_recent.log" <<'LOG'
## [2026-09-30 10:00:00] status=stdout
CMD: gh api graphql -F query=@/tmp/a.graphql
STDOUT:
jq: parse error: Invalid numeric literal
---
LOG
cat >"$tmp/home/.cache/copilot/2026-09-01-pr-review/threads.graphql" <<'EOF'
query { viewer { login } }
EOF
cat >"$tmp/home/.cache/copilot/2026-09-01-pr-review/threads.jq" <<'EOF'
.data.viewer.login
EOF
printf 'query { ignored }\n' >"$tmp/home/.cache/copilot/2026-09-01-pr-review/node_modules/ignored.graphql"
cat >"$tmp/home/.config/copilot/session-state/recent/events.jsonl" <<'JSONL'
{"type":"tool.execution_start","data":{"toolCallId":"one","toolName":"fixture-tool","arguments":"first"}}
{"type":"tool.execution_complete","data":{"toolCallId":"one","success":false,"error":"first failure"}}
{"type":"tool.execution_start","data":{"toolCallId":"two","toolName":"fixture-tool","arguments":"second"}}
{"type":"tool.execution_complete","data":{"toolCallId":"two","success":false,"error":"second failure"}}
JSONL
cat >"$tmp/home/.cache/copilot/session_retained-session.log" <<'LOG'
## [2026-08-01 10:00:00] status=stdout
CMD: echo retained-marker
STDOUT:
retained-marker
---
LOG
touch -t 202608011000 "$tmp/home/.cache/copilot/session_retained-session.log"

helper="$repo_root/chezmoi/dot_local/bin/executable_cache-scan"
audit="$(HOME="$tmp/home" "$helper" --audit --days 30 --limit 1)"
assert_contains "$audit" 'ACTUAL TOOL ERRORS'
assert_contains "$audit" 'HEURISTIC FAILURE SIGNALS'
assert_contains "$audit" 'SCRIPT ARTIFACT FAMILIES'
assert_contains "$audit" 'github-review'
assert_contains "$audit" 'second failure'
assert_not_contains "$audit" 'first failure'
assert_not_contains "$audit" 'graphql      2'

retained="$(HOME="$tmp/home" "$helper" --session retained-session)"
assert_contains "$retained" 'retained-marker'
