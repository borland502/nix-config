#!/usr/bin/env bash
# log-thinking.sh — capture agent reasoning/thinking to ~/.cache/<agent>/,
# the analogue of log-bash.sh but sourced from the session event log rather
# than a tool payload. NOT run by hand. Receives the hook payload as JSON on
# stdin and is wired as:
#   - Claude:  Stop + SubagentStop hooks (payload carries .transcript_path)
#   - Copilot: postToolUse hook (payload carries .sessionId; reasoning lives in
#              ~/.config/copilot/session-state/<id>/events.jsonl)
#
# Output: ~/.cache/<agent>/session_<id>.thinking.log, one appended block per
# fire, deduped by a per-source line cursor under ~/.cache/<agent>/.thinking-cursor.
#
# SECURITY — thinking frequently reasons about secret VALUES the agent saw
# (Kion creds, Jira/Confluence/gh tokens, age key). These logs live under
# ~/.cache/<agent>, which the gdrive unison profile syncs. Defenses here:
#   1. known secret values on disk are redacted literally before write;
#   2. token-shaped strings are redacted by pattern (no length-only rule — that
#      would clobber nix store hashes / git SHAs);
#   3. files are created 0600;
#   4. *.thinking.log and .thinking-cursor are excluded from the gdrive profile.
# These reduce but do not eliminate leakage risk; treat the logs as sensitive.
set -euo pipefail

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

agent_raw="${AGENT_NAME:-claude}"
agent=$(printf '%s' "$agent_raw" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
[[ -n "$agent" ]] || agent="claude"

# Resolve source event log + session id + flavor from the payload shape.
if printf '%s' "$input" | jq -e '.transcript_path' >/dev/null 2>&1; then
	flavor=claude
	src=$(printf '%s' "$input" | jq -r '.transcript_path // ""')
	sid=$(printf '%s' "$input" | jq -r '.session_id // ""')
elif printf '%s' "$input" | jq -e '.sessionId' >/dev/null 2>&1; then
	flavor=copilot
	sid=$(printf '%s' "$input" | jq -r '.sessionId // ""')
	src="${COPILOT_HOME:-$HOME/.config/copilot}/session-state/$sid/events.jsonl"
else
	exit 0
fi

[[ -n "$src" && -f "$src" ]] || exit 0
[[ -n "$sid" ]] || sid=$(basename "$src" .jsonl)

log_dir="$HOME/.cache/$agent"
state_dir="$log_dir/.thinking-cursor"
mkdir -p "$log_dir" "$state_dir"
logfile="$log_dir/session_${sid}.thinking.log"

# Per-source line cursor: each hook fire processes only newly-appended lines.
key=$(printf '%s' "$src" | cksum | cut -d' ' -f1)
cursor_file="$state_dir/$key"
cursor=0
[[ -f "$cursor_file" ]] && cursor=$(cat "$cursor_file" 2>/dev/null || echo 0)
[[ "$cursor" =~ ^[0-9]+$ ]] || cursor=0

total=$(wc -l <"$src" 2>/dev/null | tr -d ' ')
[[ "$total" =~ ^[0-9]+$ ]] || total=0
((total < cursor)) && cursor=0 # transcript rotated/compacted -> restart
((total > cursor)) || exit 0   # nothing new

new_lines=$(tail -n +"$((cursor + 1))" "$src" 2>/dev/null || true)
# Advance the cursor up front so empty/non-thinking turns are not reprocessed.
printf '%s' "$total" >"$cursor_file"

if [[ "$flavor" == claude ]]; then
	blocks=$(printf '%s\n' "$new_lines" | jq -r '
		select(.message.role == "assistant")
		| .message.content[]?
		| if .type == "thinking" then .thinking
			elif .type == "redacted_thinking" then "[redacted_thinking block omitted]"
			else empty end' 2>/dev/null || true)
else
	blocks=$(printf '%s\n' "$new_lines" | jq -r '
		select(.type == "assistant.message")
		| .data.reasoningText // empty
		| select(. != "")' 2>/dev/null || true)
fi

[[ -n "$blocks" ]] || exit 0

# Redact known secret values (literal) then token-shaped strings (pattern).
redact() {
	local text="$1" f v
	for f in \
		"$HOME/.cache/kion-aws-cache/AWS_ACCESS_KEY_ID" \
		"$HOME/.cache/kion-aws-cache/AWS_SECRET_ACCESS_KEY" \
		"$HOME/.cache/kion-aws-cache/AWS_SESSION_TOKEN" \
		"$HOME/.config/ops-agent/jira-token" \
		"$HOME/.config/confluence/token"; do
		[[ -r "$f" ]] || continue
		v=$(tr -d '\n\r' <"$f" 2>/dev/null || true)
		[[ ${#v} -ge 8 ]] || continue
		text="${text//"$v"/[REDACTED-SECRET]}"
	done
	printf '%s' "$text" | sed -E \
		-e 's/(AKIA|ASIA)[0-9A-Z]{16}/[REDACTED-AWS-KEY]/g' \
		-e 's/gh[posru]_[A-Za-z0-9]{20,}/[REDACTED-GH-TOKEN]/g' \
		-e 's/github_pat_[A-Za-z0-9_]{20,}/[REDACTED-GH-TOKEN]/g' \
		-e 's/AGE-SECRET-KEY-[0-9A-Z]+/[REDACTED-AGE-KEY]/g'
}

out=$(redact "$blocks")
max_chars=20000
if ((${#out} > max_chars)); then
	out="${out:0:max_chars}"$'\n''... [thinking truncated; see transcript for full text]'
fi

umask 077
{
	printf '\n## [%s] %s reasoning (session %s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$agent" "$sid"
	printf '%s\n' "$out"
	printf -- '---\n'
} >>"$logfile"
chmod 600 "$logfile" 2>/dev/null || true
