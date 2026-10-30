# Why those logs exist

The logs under `~/.cache/<agent>/session_<id>.log` (where `<agent>` is `claude` or `copilot`) are populated automatically by a Bash `PostToolUse` hook. The hook is injected into `~/.config/claude/settings.json` (Claude) and declared in `~/.config/copilot/hooks/log-bash.json` (Copilot) — both wired by [home-manager/common.nix](../../../../home-manager/common.nix). Every Bash tool call is piped through [ai-tools/scripts/log-bash.sh](../../../scripts/log-bash.sh) (deployed to `~/.local/bin/ai-tools/log-bash.sh`), which appends a structured record:

```text
## [YYYY-MM-DD HH:MM:SS] status=ok|stderr|interrupted cwd=<dir>
CMD: <command>
STDOUT: / STDERR: sections
```

`status` is a heuristic (no exit code is exposed to the hook): `interrupted`, else `stderr` when stderr is non-empty, else `ok`. Activation also enforces `~/.cache/claude` and `~/.cache/codex` → `~/.cache/copilot` as symlinks so every agent shares one log dir.

## Capture coverage and legacy failure limits

Managed command hooks also append original event payloads under
`~/.cache/copilot/agent-capture/events/<agent>/<session>/events.jsonl`.
Claude and Copilot have dedicated tool-failure hooks; Codex failure evidence
comes from native transcripts. A user timer reconciles native transcripts,
logs, tool results and session artifacts every fifteen minutes into
`agent-capture/capture/<agent>/`, with provenance in `agent-capture/manifests/`.
The collector uses local Python only: no model calls or model credits.

`cache-scan --audit` and `--transcript` read the mirrored transcripts even when
their originals are gone. Prompts and errors from all three agents work without
a legacy Bash log. Hook failures are reported separately because they can
overlap native transcript errors; do not add the two counts together.
Captured files retain their source hierarchy and timestamps. Copies update when
content changes and never remove native source data; the old sweeper's
`--prune` option is refused. Native formats are vendor-specific and adapters
need regression fixtures when upgrading a CLI.

After deployment, review and trust the changed Codex hook definitions in
`/hooks`; Codex trust is keyed to their definition hash. Sandbox policies must
permit the collector executable and its cache output directory. The timer
still recovers available native files when a hook cannot run. Neither path can
recover content a vendor never writes locally, and files created and removed
between reconciliation runs may not be copied. Do not run hook automation by
hand against real state during an investigation; use the deployed timer and
fixture tests (`task check:agent-tools`).

The legacy Bash log has two limits, measured on 2026-09-03. **An empty
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

Do not rely on the legacy `FAILURES` section. Triage a real failure from:

- **`HEURISTIC FAILURE SIGNALS`** — `cache-scan` pattern-matches error text
  in eligible legacy log output and classifies it (`nullglob-miss`,
  `stat-dialect`, `cmd-not-found`, …). These observations are leads, not verified
  failures or proof of an exit-zero error.
- **`cache-scan -t`**, whose `NATIVE TRANSCRIPTS (live and cached)` section
  reports retained error observations with the tool, command or path, and error
  text for Claude, Copilot and Codex. It also reports uncertainty when execution
  identity cannot be established. Use these transcript records for failure
  triage; inspect `HEURISTIC FAILURE SIGNALS` separately with `--audit`.
- **The user's own account** of what broke. When the log is silent, ask rather
  than concluding the command succeeded.

Never report "no failures in the window" on the strength of the `FAILURES`
section alone.

Lifecycle: the daily `compress-old-cache` timer zstd-compresses top-level cache files older than 1 day (or over 1 MB), then applies a **retention pass** — top-level `.zst` archives and subdirectories untouched for `CACHE_RETENTION_DAYS` (default 548 ≈ 1.5 years) are deleted. Capture reconciliation applies the same retention window to its nested data. Anything that must survive long-term does not belong in the cache dir.

This is *not* something a session needs to wire up — if the host has had `home-manager switch` run successfully, the hook is already firing on every Bash call. This skill consumes that log stream; it does not produce it. The companion read-side workflow lives in [flow-systematic-debugging](../../flow-systematic-debugging/SKILL.md) Phase 0.
