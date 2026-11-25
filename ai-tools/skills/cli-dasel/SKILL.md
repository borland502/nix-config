---
name: cli-dasel
description: Use when selecting, updating, or converting JSON, YAML, TOML, XML, or CSV with dasel, especially for cross-format configuration tasks and dasel v3 syntax.
---

# Query and convert structured data with dasel

dasel is already in the shared package set. Its advantage is one query language
across formats, especially TOML/XML/CSV work that would otherwise need a script.
Honor an explicitly requested tool.

## Choose a tool

```text
What is the data task?
|-- Complex JSON filters, aggregation, or an existing jq pipeline -> jq
|-- YAML-specific manipulation or comment/style handling -> yq
|-- Select/update fields across formats, or convert formats -> dasel
|-- Browse JSON/YAML interactively -> jless
|-- Discover unknown JSON key paths -> gron, then rg
`-- Intentional raw text replacement, including comments -> sd
```

Prefer a structured editor for data values; raw replacement can change unrelated
keys or break syntax. For interactive inspection see [jless](../cli-jless/SKILL.md).

## Use the deployed major version

Check `dasel version`. These examples were verified with v3.8.1; v2 tutorials
using `-r`, `-f`, or `put` are not interchangeable with v3 commands.

```sh
dasel -i json 'service.port' < config.json
dasel -i toml -o json < config.toml
dasel -i json -o yaml < config.json
dasel -i json --root 'service.port = 9090' < config.json
```

Input comes from stdin and output goes to stdout. Quote queries with single
quotes so the shell preserves expressions. Assignment returns the changed value
unless `--root` requests the full document; omitting it can accidentally replace
a config with one scalar.

For file edits, write to a separate temporary file, validate and inspect the diff,
then replace the target within the authorized edit. Never redirect output to the
same file used as input: the shell truncates it before dasel reads.

Conversion preserves representable data, not source formatting. Check comments,
types, XML attributes/namespaces, and CSV row structure before relying on a
round trip; formats do not share identical data models.

[Upstream and v3 examples](https://github.com/TomWright/dasel)
