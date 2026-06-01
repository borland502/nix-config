---
name: ops-cache-scan
description: Scan cache logs for recent activity, failures, and resumable context from ~/.cache/copilot and ~/.cache/claude.
---

# Cache Scan

Use this skill when the user asks to recover context from recent cache activity, resume prior work, or summarize failures from terminal logs.

## Why those logs exist

The logs under `~/.cache/<agent>/session_<id>.log` (where `<agent>` is `claude` or `copilot`) are populated automatically by a Bash `PostToolUse` hook. The hook is injected into `~/.config/claude/settings.json` (Claude) and declared in `~/.config/copilot/hooks/log-bash.json` (Copilot) — both wired by [home-manager/common.nix](../../../home-manager/common.nix). Every Bash tool call is piped through [chezmoi/dot_local/bin/executable_log-bash.sh](../../../chezmoi/dot_local/bin/executable_log-bash.sh) (deployed to `~/.local/bin/log-bash.sh`), which appends a structured record:

```text
## [YYYY-MM-DD HH:MM:SS] status=ok|stderr|interrupted cwd=<dir>
CMD: <command>
STDOUT: / STDERR: sections
```

`status` is a heuristic (no exit code is exposed to the hook): `interrupted`, else `stderr` when stderr is non-empty, else `ok`. Activation also enforces `~/.cache/claude` → `~/.cache/copilot` as a symlink so both agents share one log dir.

This is *not* something a session needs to wire up — if the host has had `home-manager switch` run successfully, the hook is already firing on every Bash call. This skill consumes that log stream; it does not produce it. The companion read-side workflow lives in [flow-systematic-debugging](../flow-systematic-debugging/SKILL.md) Phase 0.

## Inputs

- `--days N` lookback by file mtime (defaults to `2`).
- `--date YYYY-MM-DD` to restrict records to a header date.
- `--session ID` to focus a single session log.
- `--limit N` timeline length under `--verbose` (defaults to `10`).
- `-v|--verbose` add the command timeline and keyword scan (default output is
  intentionally terse to keep token cost low — read the default first and only
  reach for `--verbose` when you need the full timeline).

## Procedure

1. Run the helper script (terse): `cache-scan`
2. Wider lookback: `cache-scan --days 5`
3. Single session, full detail: `cache-scan --session 4e8838e2 --verbose`

## What To Extract

`cache-scan` already structures this; read its sections directly:

- **SESSIONS** (default) — one line per session: id, command / stderr / interrupt
  counts, last status + command.
- **FAILURES** (default) — commands with `status=stderr|interrupted`; the concrete
  resume points.
- **TIMELINE** (`--verbose`) — `[ts] status :: cmd` from the newest session; the
  tail is where work was interrupted.
- **KEYWORD HITS** (`--verbose`) — heuristic backstop for errors a `status=ok`
  line missed (and for pre-structured logs).

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
