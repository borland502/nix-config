# Inputs

- `--days N` lookback by file mtime (defaults to `2`).
- `--date YYYY-MM-DD` to restrict records to a header date.
- `--session ID` to focus a single session log. Without `--days` or `--date`,
  this searches retained logs instead of inheriting the two-day default.
- `--limit N` timeline / decision length (defaults to `10`). In JSON/evidence,
  this is a per-array cap for native, hook and heuristic observations.
- `-t|--transcript` enrich with the free native signal the Bash log never
  captures — your typed prompts, the assistant's decision text, the files
  changed, and the non-Bash tool tally. Claude reads
  its session transcripts (`~/.config/claude/projects/*/<id>.jsonl`, older runs
  under `~/.claude/projects`) + prompt-input log
  (`~/.config/claude/history.jsonl`); Copilot reads its event stream
  (`~/.config/copilot/session-state/<id>/events.jsonl`) plus the process log
  (`~/.config/copilot/logs/process-*.log`) for the model and real error lines.
  Codex reads `CODEX_HOME/sessions` and `archived_sessions`, with fallbacks to
  `~/.config/codex` and `~/.codex`, deduplicated by real path. Its errors,
  prompts, and decisions work without a cache log, including `--session ID`.
  Additional Claude/Copilot tool/diff enrichment joins cache logs by session id. Read-only — no
  model calls, no credits. Needs `jq` and Python standard library.
- `--diffs` implies `-t` and additionally reconstructs the exact edits — Claude
  from the transcript's verbatim `old_string`/`new_string`, Copilot from the
  `apply_patch` V4A payloads. Capped by `--limit`; behind its own flag because
  diffs are token-heavy.
- `--classify` aggregate failure categories across the window (`--days`
  defaults to 21 here), including the `.zst` archives: buckets each record's
  output into named categories (`stale-aws-creds`, `stat-dialect`,
  `zsh-nullglob`, `zsh-word-split`, `gh-graphql-jq`, `jq-non-json-input`, …)
  and prints counts plus example commands. Use for trend triage ("what keeps
  failing?"), not
  single-session debugging. Heuristic — the log has no exit codes; records
  whose command is itself a log sweep are excluded, but real output quoting a
  marker still counts. Treat counts as leads. Needs `python3`.
- `--audit` review recurring operational waste in one pass. It defaults to 30
  days and separates `ACTUAL TOOL ERRORS`, `HEURISTIC FAILURE SIGNALS`, and
  recursively discovered `SCRIPT ARTIFACT FAMILIES`. Dependency/build trees
  are excluded. Use this for remedy design; use `--transcript` for one failure.
- `--json` / `--evidence` return machine evidence with source locators. Each
  observation array contains its newest `--limit N` records in timestamp order;
  zero emits no observations. `record_limit` states the cap; `record_counts`
  reports `total`, `selected` and `omitted` for each array, including empty ones.
  Existing native error/ambiguity counts describe all eligible observations.
  Selected command/output text is capped at 2000 characters, with original
  character counts and truncation flags. `--full-output` lifts these text caps
  only; the record cap remains. Originals and the native event index retain
  complete evidence. Hook and native counts can overlap; do not add them blindly.
- `-v|--verbose` add the command timeline and keyword scan (default output is
  intentionally terse to keep token cost low — read the default first and only
  reach for `--verbose` when you need the full timeline).

## Procedure

1. Run the helper script (terse): `cache-scan`
2. Wider lookback: `cache-scan --days 5`
3. Single session, full detail: `cache-scan --session 4e8838e2 --verbose`
4. Recover *intent* (prompts, decisions, edited files), not just commands:
   `cache-scan --session 4e8838e2 --transcript`
5. Reconstruct the exact edits made (Claude or Copilot):
   `cache-scan --session 4e8838e2 --diffs`
6. Trend triage — what keeps failing across sessions:
   `cache-scan --classify` (or `--classify --days 60` for a longer horizon)
7. Broad remediation audit — confirmed errors, heuristic signals, and repeated
   script families: `cache-scan --audit` (or `--audit --days 60`)

## What To Extract

Audit errors are ordered by event timestamp, with session and command
provenance. Its date/window filters apply to events rather than transcript
mtime. Script families include compressed scripts, deduplicate decompressed
content, and omit generated assets and helper query snapshots. Documentation
and self-audit reads are excluded from heuristic signals; actual failed tools
remain visible. Counts are leads, not failure-rate statistics.

`cache-scan` already structures this; read its sections directly:

- **SESSIONS** (default) — one line per session: id, command / stderr / interrupt
  counts, last status + command.
- **FAILURES** (default) — commands with `status=stderr|interrupted`. **In
  practice always empty** on current harnesses, and it says so in its own output
  rather than printing a reassuring `none`; see "The log cannot see failures"
  above. Only archived pre-July logs still populate it.
- **TOOL ERRORS** (`-t`) — the tool calls that actually failed, joined from the
  transcript back to the tool name and its command/path. The section the
  `FAILURES` line points you to, and the one to read when triaging.
- **ARTIFACTS** (default) — standalone plan/spec/design/handoff/note/resume
  files in the cache root (`PHASE*`, `*handoff*`, `*plan*.md*`, `*spec*.md*`,
  `*design*.md*`, `*note*.md*`, `*resume*.md*`), newest first, including `.zst`
  archives. These are hand-written context the `session_*.log` stream never
  contained; open one directly (`zstdcat` for `.zst`) to resume.
- **SCRIPTS** (default) — reusable helper scripts a prior session wrote to the
  cache root (code / query extensions: `.py`, `.go`, `.sh`, `.js`, `.ts`, `.jq`,
  `.graphql`, `.nix`, `.sql`, …), newest first, including the `.zst` archives
  `compress-old-cache` makes after a day. Check this **before** rewriting a
  helper: an exact `ls <name>.py` misses the archived `<name>.py.zst` and makes
  an existing script look gone. `.zst` rows are tagged `(zstdcat)` — recover
  with `zstdcat file.zst > file`. Widen with `--days` to reach older archives.
- **TIMELINE** (`--verbose`) — `[ts] status :: cmd` from the newest session; the
  tail is where work was interrupted.
- **KEYWORD HITS** (`--verbose`) — heuristic backstop for errors a `status=ok`
  line missed (and for pre-structured logs).
- **NATIVE TRANSCRIPT ENRICHMENT** (`--transcript`) — PROMPTS (your asks),
  DECISIONS (assistant text), FILE EDITS (paths × count), and NON-BASH TOOLS for
  the focused session. This is the *why* behind the commands; the Bash log only
  has the *what*. Empty PROMPTS usually means the session is still live
  (`history.jsonl` flushes at session end). Copilot sessions additionally show
  `AGENT/MODEL` and an `OPERATIONAL` block (process-log model + curated error
  lines — useful when triaging tool/MCP failures).
- **DIFFS** (`--diffs`) — the exact per-edit changes for the focused session;
  read these when you need to see *what* a prior run actually wrote, not just
  which files it touched.
- **CLASSIFY** (`--classify`) — category counts + example commands across the
  window. The input for remediation planning (which skill/doc/helper to fix),
  not for debugging one failure.
- **ACTUAL TOOL ERRORS / HEURISTIC FAILURE SIGNALS / SCRIPT ARTIFACT FAMILIES**
  (`--audit`) — the consolidated remediation view. Keep the first two classes
  distinct: heuristic matches are leads, not confirmed failed executions.
