---
name: cli-lnav
description: Use when correlating timestamped logs across files, navigating log events, or summarizing recognized log records with lnav SQL and headless output.
---

# Correlate logs with lnav

lnav combines recognized timestamped logs into a time-oriented view and exposes
records to SQL. Honor an explicitly requested tool.

## Choose a tool

```text
What do you need from logs?
|-- Literal/regex match or a small surrounding excerpt -> rg
|-- Exact fields in JSON/JSONL -> jq
|-- Time correlation across files, navigation, or log SQL -> lnav
|-- Nested JSON browsing -> jless
`-- Text inside compressed archives or documents -> rga
```

See [rga](../cli-rga/SKILL.md) for extraction; prefer lnav when ordering and
recognized log fields matter.

## Use a bounded set of files

```sh
lnav app.log worker.log
lnav -n -c ';SELECT count(*) AS total FROM all_logs' -c ':write-csv-to -' app.log worker.log
```

The first command opens an interactive viewer. The second prints a CSV count
without a TUI; use headless mode for agent captures. SQL starts with `;`; lnav
commands start with `:`.

Inspect recognition before trusting a query: event grouping, timestamps, time
zones, and `log_level` depend on the detected format. Unknown/multiline records
can change counts. Start with known fixture-sized files and select only the
columns and rows needed; use `LIMIT` for event excerpts.

Pass filenames explicitly so lnav does not open default system logs. Avoid
recursive scans or installing formats as a side effect of ordinary inspection.
Use `rg` when a format is unrecognized and the question is just text search.

[Upstream](https://github.com/tstack/lnav)
