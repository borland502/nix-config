---
name: ops-cache-scan
description: Use when investigating why a recent command or tool failed, resuming context from an earlier session, or when asked what happened previously — scans the ~/.cache/claude and ~/.cache/copilot session logs. Prefer this over hand-rolled greps (rg/find) across the cache dir.
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
  `zsh-nullglob`, `gh-graphql-jq`, `jq-non-json-input`, …) and prints counts
  plus example commands. Use for trend triage ("what keeps failing?"), not
  single-session debugging. Heuristic — the log has no exit codes, and a
  session that sweeps these logs can still self-trip; treat counts as leads.
  Needs `python3`.
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
- **FAILURES** (default) — commands with `status=stderr|interrupted`; the concrete
  resume points.
- **ARTIFACTS** (default) — standalone plan/handoff/note files in the cache root
  (`PHASE*`, `*handoff*`, `*plan*.md`, `*note*.md`, `*resume*.md`, plus `.zst`
  archives), newest first. These are hand-written context the `session_*.log`
  stream never contained; open one directly (`zstdcat` for `.zst`) to resume.
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
