---
name: cli-dasel
description: Use when querying or modifying structured-data files in a format-agnostic way (JSON, YAML, TOML, XML, CSV) from the shell. dasel speaks all five formats with a single selector syntax — pick it over jq/yq/xq when the task crosses formats or when the file format is variable.
---

# dasel

`dasel` (data-selector) is a single CLI that reads, writes, and converts JSON, YAML, TOML, XML, and CSV using a unified selector syntax. Use it instead of `jq` + `yq` + `xq` when the task spans formats or when the format isn't known up front.

## Quick Reference

```bash
# Read (auto-detected format from extension; -r overrides)
dasel -f file.yaml '.app.port'
dasel -r json -w json '.items.[0].name' file.json

# Write (-w sets output format; supports format conversion in one call)
dasel -f file.yaml -w json '.app'
dasel -f file.toml -w yaml '.'

# Modify in place (use the put subcommand)
dasel put -f file.yaml -v "8080" '.app.port'
dasel put -f file.yaml -t int -v 8080 '.app.port'    # explicit type
dasel put -f file.yaml -v "true" -t bool '.app.tls'

# Append to a list
dasel put -f file.yaml -t string -v "alice" '.users.[]'

# Delete a node
dasel delete -f file.yaml '.app.tls'

# Validate (parses without writing)
dasel validate -f file.toml
```

## Subcommands

`dasel <subcommand> [flags]` — each has its own `--help`:

| Subcommand | Use |
|---|---|
| `select` (default) | Read a value out |
| `put` | Set a value |
| `delete` | Remove a node |
| `validate` | Parse-only sanity check |
| `convert` | Read in one format, write in another |

## Project Context

This repo lists `dasel` in [chezmoi/dot_config/instructions/agent-defaults.md](../../../chezmoi/dot_config/instructions/agent-defaults.md) under the shared tooling defaults: "Prefer these repo-managed tools over generic fallbacks when they fit the task: … `jq`/`yq`/`dasel` for structured data". Reach for dasel when:

- Editing a `.toml` chezmoi config from a script (jq doesn't read TOML).
- Converting between TOML and JSON for diffing or templating.
- Touching the [chezmoi/.chezmoiexternal.toml.tmpl](../../../chezmoi/.chezmoiexternal.toml.tmpl) entries programmatically — though hand-editing is preferred for the small entry set here.

## Selector Syntax

dasel selectors look like jq paths but with explicit `.` separators:

```
.app.port                     # nested object access
.items.[0]                    # array index
.items.[*].name               # all array elements' name field
.items.(.kind=worker).host    # filter by predicate
```

Differences from jq:
- Indices are `.[0]` not `[0]`.
- Filter is `.(.predicate)` not `select(.predicate)`.
- No pipe-chained transforms — dasel is mostly read/write, not transform-heavy.

## Common Idioms

### Convert a file in place from YAML to JSON

```bash
tmp=$(mktemp --suffix=.json)
dasel -f config.yaml -w json '.' > "$tmp" && mv "$tmp" config.json
```

### Bulk-add a key across multiple TOML files

```bash
for f in *.toml; do
  dasel put -f "$f" -t string -v "$(date +%Y-%m-%d)" '.metadata.last_touched'
done
```

### Drift detection (current vs desired)

```bash
current=$(dasel -f file.yaml '.app.port' 2>/dev/null || echo "")
if [ "$current" != "$desired" ]; then
  dasel put -f file.yaml -v "$desired" '.app.port'
fi
```

## References

- `references/help.txt` — captured top-level `dasel --help` (dasel 2.8.1).
- `references/select-help.txt` — captured `dasel select --help`.
- Project: <https://github.com/TomWright/dasel> — README has the most current syntax examples.
- Docs: <https://daseldocs.tomwright.me/>.

## Notes

- dasel auto-detects format from file extension when `-f` is given. Use `-r <format>` to override on stdin (`cat file | dasel -r yaml '.x'`).
- For pure JSON work, jq has a richer transform vocabulary — use jq for filter/map/reduce pipelines and dasel for cross-format read/write.
- The `put` flag `-t` is required for non-string types (`int`, `float`, `bool`, `string`); without it, the value is written as a string in YAML/JSON, which can break consumers expecting a typed value.
