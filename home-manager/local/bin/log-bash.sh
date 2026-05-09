#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
sid=$(printf '%s' "$input" | jq -r '.session_id // "nosid"')
resp=$(printf '%s' "$input" | jq -r '
  if .tool_response == null then ""
  elif (.tool_response | type) == "string" then .tool_response
  else .tool_response | tostring
  end')

agent_raw="${AGENT_NAME:-claude}"
agent=$(printf '%s' "$agent_raw" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
if [[ -z "$agent" ]]; then
	agent="claude"
fi

log_dir="$HOME/.cache/$agent"
logfile="$log_dir/session_${sid}.log"
mkdir -p "$log_dir"

{
	printf '\n## [%s]\n' "$(date '+%Y-%m-%d %H:%M:%S')"
	printf 'CMD: %s\n' "$cmd"
	printf 'OUTPUT:\n%s\n' "$resp"
	printf -- '---\n'
} >>"$logfile"
