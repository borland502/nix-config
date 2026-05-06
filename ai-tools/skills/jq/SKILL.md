---
name: jq
description: Use when filtering, transforming, or generating JSON from the shell. Covers idioms for safe field access, conditional pipelines, in-place file edits, and the jq patterns used by this repo's home-manager activation hooks (~/.config/claude/settings.json mutations) and ops-agent scripts.
---

# jq

Use this skill when the user wants to filter, transform, query, or build JSON. `jq` is on the shared tooling list; prefer it over `grep -o` / `sed` against JSON.

## Quick Reference

```bash
# Pretty-print or validate
jq . file.json
jq -e . file.json    # exits non-zero if input isn't valid JSON

# Field access (safe with //)
jq -r '.foo.bar // "default"' file.json
jq -r '.foo.bar // empty' file.json    # silent omission

# Filter array members
jq '.items[] | select(.enabled == true)' file.json
jq '[.items[] | select(.enabled)]' file.json   # wrap in array

# Build an object
jq -n --arg name "$NAME" --argjson n "$COUNT" '{name: $name, count: $n}'

# In-place edit (atomic, no `-i` flag — write to tmp then mv)
tmp=$(mktemp)
jq '.key = "new value"' file.json > "$tmp" && mv "$tmp" file.json

# Set / unset deep keys
jq '.a.b.c = "x"' file.json
jq 'del(.a.b)' file.json
```

## Project Context

This repo's [home-manager/common.nix](../../../home-manager/common.nix) uses jq inside Home Manager activation hooks to **idempotently** edit `~/.config/claude/settings.json`:

```bash
_tmp=$(mktemp)
jq --arg path "$_market_path" \
  '.extraKnownMarketplaces["nix-config-dev"] = {source: {source: "directory", path: $path}}
   | .enabledPlugins["nix-config-tools@nix-config-dev"] = true' \
  "$_settings" > "$_tmp" && mv "$_tmp" "$_settings"
```

The pattern: read with `jq -r '.path // ""'` to detect drift before writing, then write with `jq … > tmp && mv tmp orig`. Never use shell redirection back to the input file — the shell truncates it before jq reads.

The `ops-agent` Python helper at [home-manager/local/bin/ops-agent.py](../../../home-manager/local/bin/ops-agent.py) shells out to `jq` for parsing Jira REST responses; see those call sites for examples of `--arg`/`--argjson` use.

## Common Idioms

### Detect-then-write (drift-safe in-place mutation)

```bash
current=$(jq -r '.path // ""' file.json)
if [ "$current" != "$desired" ]; then
  tmp=$(mktemp)
  jq --arg path "$desired" '.path = $path' file.json > "$tmp" && mv "$tmp" file.json
fi
```

### Filter then count

```bash
jq '[.items[] | select(.kind == "error")] | length' log.json
```

### Transform a list of objects

```bash
jq '.users | map({id: .id, label: "\(.first) \(.last)"})' users.json
```

### Stream large files (avoid loading into memory)

```bash
jq -c '.items[]' big.json | while read -r line; do …; done
```

### Merge two JSON objects (right wins)

```bash
jq -s '.[0] * .[1]' base.json overlay.json
```

### Convert between formats (with `yq`)

```bash
yq -o json . file.yaml | jq '.app.config'
jq -r '.users[].name' users.json | yq -p csv -o yaml .
```

## Flags Worth Knowing

| Flag | Meaning |
|---|---|
| `-r` | Raw output (no quotes around strings) |
| `-c` | Compact one-line per top-level value |
| `-s` | Slurp all inputs into a single array |
| `-n` | Null input — for building from scratch with `--arg` / `--argjson` |
| `-e` | Exit 1 on null/false output (for use in conditionals) |
| `-R` | Raw input (each line as a string) |
| `--arg name value` | Pass a string-typed value into the program |
| `--argjson name value` | Pass a JSON-typed value (numbers, booleans, objects) |
| `--slurpfile name path` | Slurp another file as a JSON array bound to `$name` |

## References

- `references/help.txt` — captured `jq --help` output (this version: jq-1.8.1).
- Manual: <https://jqlang.org/manual/> — the canonical reference for filter syntax.
- Tutorial: <https://jqlang.org/tutorial/>.
- Cookbook: <https://github.com/stedolan/jq/wiki/Cookbook>.

## Notes

- jq's filter language is its own DSL — neither shell nor JavaScript. Pipe (`|`) chains filters; comma (`,`) emits multiple outputs.
- Use `--arg` / `--argjson` for ALL externally-supplied values to avoid quoting/injection issues. Never interpolate shell variables directly into the filter string.
- jq does not have a built-in in-place flag (no `-i`). Use the `tmp=$(mktemp); … > "$tmp" && mv "$tmp" file` pattern.
- For YAML, use `yq` (a separate skill). `yq` is jq-compatible in syntax, so most idioms transfer.
