# TODO

## cache-scan native-transcript enrichment (`-t|--transcript`)

### Goal

Let `cache-scan` recover *intent*, not just commands. The Bash `PostToolUse` log
(`~/.cache/<agent>/session_<id>.log`) records only `CMD/STDOUT/STDERR`. Claude
Code already writes the rest to disk for free — the full session transcript and
the prompt-input log — so the reader can join and surface it with no model calls
and no credits.

### Free native sources joined by session id

| Signal | Source (read-only, no credits) |
| --- | --- |
| Your typed prompts | `~/.config/claude/history.jsonl` (keyed by `sessionId`) |
| Assistant decision text | `~/.config/claude/projects/*/<id>.jsonl` (`type==assistant` → `content[].text`) |
| Files Edit/Write changed | transcript `tool_use` in `Edit`/`Write`/`NotebookEdit` → `input.file_path` |
| Non-Bash tool tally | transcript `tool_use` where `name != Bash` |
| Older runs | `~/.claude/projects/*/<id>.jsonl` (pre-XDG location) |

Join key: cache log `session_<id>.log` ⇄ `history.jsonl.sessionId` ⇄ transcript
filename `<id>.jsonl`. All three use the same session UUID.

### Done (drafted + tested in this branch)

- [x] `chezmoi/dot_local/bin/executable_cache-scan`: add `-t|--transcript` flag,
      `find_transcript`, `distill_session`, `base_id` (normalizes
      `.skills`/`.thinking` companion logs + dedupes), and a
      `NATIVE TRANSCRIPT ENRICHMENT` section emitting PROMPTS / DECISIONS /
      FILE EDITS / NON-BASH TOOLS.
- [x] `jq` guard (graceful skip), home-dir redaction on paths, terse output.
- [x] `ai-tools/skills/ops-cache-scan/SKILL.md`: document the flag in Inputs,
      Procedure, and What-To-Extract.
- [x] Validated: `bash -n` parses; real session shows prompts + decisions +
      edited files; default mode unchanged; Copilot-only session degrades
      gracefully; `-t -v` exits 0.
- [x] **Copilot parity**: `distill_copilot` reads
      `~/.config/copilot/session-state/<id>/events.jsonl` — prompts
      (`user.message`, `<skill-context>` noise filtered), decisions
      (`assistant.message`), file edits (`apply_patch` V4A markers), tool tally
      (`tool.execution_start.toolName`), and an `AGENT/MODEL` line. (Used
      `events.jsonl` over `command-history-state.json` — keyed by session, full
      prompt text.)
- [x] **Operational context**: `OPERATIONAL` block surfaces the model and the
      curated real error lines from the matching
      `~/.config/copilot/logs/process-*.log` (benign ERROR-level lifecycle
      noise filtered out).
- [x] **File-edit diffs** (`--diffs`): reconstructs exact edits from the
      transcript's verbatim `old_string`/`new_string` (Claude) and the
      `apply_patch` V4A payloads (Copilot), capped by `--limit`. Sourced from
      the transcript, **not** `~/.claude/file-history/<id>/<hash>@vN` — those
      snapshots carry no hash→path manifest, so the transcript inputs are the
      exact, keyed, free source.
- [x] Dispatcher: `distill_session` tries the Claude transcript first, then the
      Copilot event stream. SKILL.md updated for `--diffs` + Copilot parity.

### To ship

- [ ] Deploy: `task switch` (runs `chezmoi apply`) so `~/.local/bin/cache-scan`
      updates; confirm `cache-scan --session <id> -t` on a live host.
- [ ] Lint: `task lint:md` (this file + SKILL.md), and `shfmt`/shellcheck on the
      script if wired into the pre-commit chain.
- [ ] Commit script + skill doc together; do not hand-edit the deployed copy.

### Decided against (not free, or not worth the tokens)

- Telemetry (`~/.claude/telemetry/1p_failed_events.*.json`): diagnostic only,
  no cost/token data — skipped.
- Thinking text: signature-only in transcripts too — nothing to redirect.

> Prior TODO backlog (tool-skill additions, tool ingestion) was truncated per
> request; recover it with `git show HEAD:TODO.md` if needed.
