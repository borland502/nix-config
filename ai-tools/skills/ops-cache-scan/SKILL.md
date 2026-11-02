---
name: ops-cache-scan
description: Use when asked to read, find, or resume today's handoff; resuming context from an earlier session; investigating a recent command or tool failure; or asked what happened previously.
---

# Cache scan

Recover recent intent, handoffs and command evidence with the existing read-side
`cache-scan` helper before reconstructing work from memory or rewriting helpers.
Use focused output first; logs and transcripts can contain credentials and
sensitive source. Redact excerpts and never paste whole sessions by default.

## Choose the smallest useful view

| Request | Start with |
| --- | --- |
| Recent activity or today's handoff | `cache-scan` or `cache-scan --date YYYY-MM-DD` |
| Resume a known session | `cache-scan --session ID --transcript` |
| Investigate a failing tool | `cache-scan --session ID --transcript` |
| Exact prior edits | `cache-scan --session ID --diffs` |
| Recurring patterns | `cache-scan --classify --days N` |
| Remedy design across sessions | `cache-scan --audit --days N` |

Use `--limit N` to bound excerpts; `--verbose` adds a timeline only when needed.
`--session` without a date/window searches retained records rather than assuming
the default two-day window. For machine-consumable bounded evidence use
`--json` or `--evidence`: `--limit N` caps each native, hook and heuristic
array to its newest N records; zero emits none. Totals and omitted counts remain.
To retain selected records' full text, combine either with `--full-output`
(record caps still apply) and redirect into a named private cache artifact; record its
path, byte count and hash when handing it to a reviewer. Inspect `cache-scan --help` for supported flags.
Do not expand a broad audit when one invocation's evidence will answer the ask.

Read [modes and output](references/modes-and-output.md) for source-specific
enrichment, section interpretation and archive retrieval. Read
[capture provenance](references/capture-provenance.md) when diagnosing missing
records, hooks, native capture coverage or retention; it explains the legacy
format and collector limits. Neither reference is required for every lookup.

## Evidence rules

Distinguish actual failed invocations from heuristic text matches. A successful
`bat` of documentation containing `ExpiredToken` is not an AWS failure. A
nonzero exit establishes failure, not its cause. Correlate wrapper and native
events by invocation identity/provenance and timestamps before counting; two
representations of one command are one failure. Hook and transcript totals may
overlap and must not be added blindly.

The legacy Bash log has no reliable exit status: failed tool calls can be
absent and stderr can be folded into stdout. An empty `FAILURES` section is
absence of evidence, never proof of no failures. Transcript `TOOL ERRORS` and
audit `ACTUAL TOOL ERRORS` are stronger evidence; `HEURISTIC FAILURE SIGNALS`,
keyword matches and classification counts are leads. Verify the raw command,
result, session and timestamp before attributing a cause or changing a skill.
Counts are not failure rates without a known denominator and capture coverage.

When resuming, inspect the latest handoff/progress ledger and referenced
artifacts, then corroborate commit IDs and working-tree state. Preserve existing
authorization and unrelated changes. Record missing or stale evidence instead
of confidently redispatching completed work.

## Find artifacts without dumping logs

Start with uncompressed files. Check listed `.zst` archives when those contain
no useful example; use `zstdcat` on the specific named archive. The SCRIPTS
section includes archived helpers: a missing `name.py` may still exist as
`name.py.zst`. Search retained artifacts before recreating scripts. Keep any
recovered file in a named cache path. Cache retention is finite; important
long-term product records belong in their approved durable destination.

This skill consumes logs; it does not configure or run automation hooks. Do not
invoke live collectors or sweepers manually during an investigation. Use fixture
tests (`task check:agent-tools`) for changed capture behavior. The source helper
is `chezmoi/dot_local/bin/executable_cache-scan`, installed as
`~/.local/bin/cache-scan`; it uses local tools without model calls.

Return recent activity, confirmed failures separately from heuristic signals,
one to three concrete resume actions, and confidence with missing evidence.
Use short redacted examples linked to artifact paths, not unsupported causal
claims or promises that the vendor recorded everything.
