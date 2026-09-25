#!/usr/bin/env bash
# log-instructions.sh — InstructionsLoaded hook logger for Claude Code.
#
# NOT run by hand. Wired as an InstructionsLoaded hook in settings.json by the
# ensureClaudeHook activation (home-manager/common.nix). Fires whenever Claude
# loads an instruction file (CLAUDE.md, CLAUDE.local.md, .claude/rules/*.md) —
# at session start, on nested-directory traversal, on path-glob match, and
# after compaction — and appends a record to the canonical
# ~/.cache/<agent>/session_<id>.log stream:
#
#   ## [YYYY-MM-DD HH:MM:SS] status=ok event=instructions cwd=<dir>
#   CMD: InstructionsLoaded reason=<reason> file=<absolute path>
#   ---
#
# This is the per-session ground truth of which federated instruction files
# actually loaded: transcripts do NOT record the claudeMd injection, so without
# this log "did my CLAUDE.md load?" is unanswerable after the fact. Copilot has
# no equivalent event. Side-effect-only hook — Claude ignores the exit code.
set -euo pipefail

input=$(cat)

event=$(printf '%s' "$input" | jq -r '.hook_event_name // ""')
[[ "$event" == "InstructionsLoaded" ]] || exit 0

file_path=$(printf '%s' "$input" | jq -r '.file_path // "?"')
reason=$(printf '%s' "$input" | jq -r '.reason // "?"')
sid=$(printf '%s' "$input" | jq -r '.session_id // "nosid"')
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')

agent_raw="${AGENT_NAME:-claude}"
agent=$(printf '%s' "$agent_raw" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
[[ -n "$agent" ]] || agent="claude"

log_dir="$HOME/.cache/$agent"
logfile="$log_dir/session_${sid}.log"
mkdir -p "$log_dir"
umask 077

{
	printf '\n## [%s] status=ok event=instructions cwd=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${cwd:-?}"
	printf 'CMD: InstructionsLoaded reason=%s file=%s\n' "$reason" "$file_path"
	printf -- '---\n'
} >>"$logfile"
chmod 600 "$logfile" 2>/dev/null || true
