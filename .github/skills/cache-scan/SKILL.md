---
name: cache-scan
description: Scan cache logs for recent activity, failures, and resumable context from ~/.cache/copilot and ~/.cache/claude.
---

# Cache Scan

Use this skill when the user asks to recover context from recent cache activity, resume prior work, or summarize failures from terminal logs.

## Inputs

- Optional date in `YYYY-MM-DD` format. Defaults to today.
- Optional `--days N` lookback (defaults to `1`).

## Procedure

1. Run the helper script:
   `cache-scan`
2. For a wider lookback:
   `cache-scan --days 3`
3. For a specific date:
   `cache-scan --date 2026-01-31`

## What To Extract

- Most recent command activity (latest files and timestamps).
- Frequent failure signatures (`error`, `failed`, `traceback`, `permission denied`, `exit code`).
- Candidate "resume points" from the latest logs:
  - Last successful command sequence.
  - Last failed command and immediate follow-up attempts.
  - Related files and tools implicated by the logs.

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
- Implementation source is `home-manager/local/bin/cache-scan.sh` and is exposed via Home Manager as `~/.local/bin/cache-scan`.
