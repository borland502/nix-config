---
name: ops-cache-scan
description: Use when investigating why a recent command or tool failed, resuming context from an earlier session, or when asked what happened previously — scans the ~/.cache/claude and ~/.cache/copilot session logs. Prefer this over hand-rolled greps (rg/find) across the cache dir. Also read it before concluding a window had no failures: failed commands never reach the log.
---

# Cache Scan

Use this skill when the user asks to recover context from recent cache activity, resume prior work, or summarize failures from terminal logs.

## Why those logs exist

The logs under `~/.cache/<agent>/session_<id>.log` (where `<agent>` is `claude` or `copilot`) are populated automatically by a Bash `PostToolUse` hook. The hook is injected into `~/.config/claude/settings.json` (Claude) and declared in `~/.config/copilot/hooks/log-bash.json` (Copilot) — both wired by [home-manager/common.nix](../../../home-manager/common.nix). Every Bash tool call is piped through [ai-tools/scripts/log-bash.sh](../../scripts/log-bash.sh) (deployed to `~/.local/bin/ai-tools/log-bash.sh`), which appends a structured record:

```text
## [YYYY-MM-DD HH:MM:SS] status=ok|stderr|interrupted cwd=<dir>
CMD: <command>
STDOUT: / STDERR: sections
```

`status` is a heuristic (no exit code is exposed to the hook): `interrupted`, else `stderr` when stderr is non-empty, else `ok`. Activation also enforces `~/.cache/claude` → `~/.cache/copilot` as a symlink so both agents share one log dir.

### The log cannot see failures — read this before triaging one

Two limits, both measured on 2026-09-03, and together they mean **an empty
`FAILURES` section is absence of evidence, never evidence of absence**:

1. **A Bash call that exits non-zero produces no record at all.** The
   `PostToolUse` hook does not fire for a failed Bash tool call, so the command,
   its output, and its error are absent from the log entirely — not logged as
   `ok`, simply missing. A probe (`ls /nonexistent-path`, exit 2) left zero
   trace in its session log.
2. **`stderr` is folded into `stdout` by the harness.** The Bash tool result now
   carries `stderr: ""` on every call and puts the error text in `stdout`, so
   the `status=stderr` branch can no longer fire. Measured across the log
   corpus: 84 `status=stderr` records in 2026-06, then **0** across ~16,700
   commands in 2026-07 through 2026-09.

So `FAILURES (stderr|interrupted): none` is what you will always see. Triage a
real failure from these instead, in order:

- **`SILENT FAILURES (exit-0 errors, heuristic)`** — `cache-scan` pattern-matches
  error text inside `STDOUT` and classifies it (`nullglob-miss`, `stat-dialect`,
  `cmd-not-found`, …). This is now the log's primary failure signal.
- **`cache-scan -t`**, whose `TOOL ERRORS` section reads the failures out of the
  transcript, where they *are* recorded — the failing tool, its command or path,
  and the error text, for Claude (`is_error` tool results) and Copilot
  (`tool.execution_complete` with `success: false`) alike. This is the real
  failure list; reach for `-t` the moment triage is the goal.
- **The user's own account** of what broke. When the log is silent, ask rather
  than concluding the command succeeded.

Never report "no failures in the window" on the strength of the `FAILURES`
section alone.

Lifecycle: `compress-old-cache` (hook + daily timer) zstd-compresses top-level cache files older than 1 day (or over 1 MB), then applies a **retention pass** — top-level `.zst` archives and subdirectories untouched for `CACHE_RETENTION_DAYS` (default 548 ≈ 1.5 years) are deleted. Subdirectories are never compressed, only pruned, so anything that must survive long-term does not belong in the cache dir.

This is *not* something a session needs to wire up — if the host has had `home-manager switch` run successfully, the hook is already firing on every Bash call. This skill consumes that log stream; it does not produce it. The companion read-side workflow lives in [flow-systematic-debugging](../flow-systematic-debugging/SKILL.md) Phase 0.

## Inputs

- `--days N` lookback by file mtime (defaults to `2`).
- `--date YYYY-MM-DD` to restrict records to a header date.
- `--session ID` to focus a single session log.
- `--limit N` timeline / decision length (defaults to `10`).
- `-t|--transcript` enrich with the free native signal the Bash log never
  captures — your typed prompts, the assistant's decision text, the files
  changed, and the non-Bash tool tally. Works for **both agents**: Claude reads
  its session transcripts (`~/.config/claude/projects/*/<id>.jsonl`, older runs
  under `~/.claude/projects`) + prompt-input log
  (`~/.config/claude/history.jsonl`); Copilot reads its event stream
  (`~/.config/copilot/session-state/<id>/events.jsonl`) plus the process log
  (`~/.config/copilot/logs/process-*.log`) for the model and real error lines.
  Joined to the cache logs by session id. Read-only — no model calls, no
  credits. Needs `jq`.
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

## What To Extract

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

## Output Contract

Return a concise summary with:

1. `Recent Activity`: top directories/files by recency.
2. `Failure Signals`: grouped patterns with hit counts.
3. `Resume Candidates`: 1-3 concrete next actions.
4. `Confidence`: high/medium/low and what is missing.

## Notes

- Prefer `rg` and `fd`/`find` for speed.
- Avoid dumping whole logs unless asked; include short excerpts only.
- Do not expose secrets; redact tokens and keys in snippets.
- Implementation source is `chezmoi/dot_local/bin/executable_cache-scan`, deployed by chezmoi to `~/.local/bin/cache-scan`.
