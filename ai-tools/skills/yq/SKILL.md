---
name: yq
description: Use when filtering, transforming, or generating YAML (and JSON, TOML, XML, CSV, properties) from the shell. yq is mikefarah/yq — Go-based, jq-syntax-compatible. Pairs with the jq skill (same idioms, different format) and is the project's preferred YAML processor.
---

# yq (mikefarah/yq)

`yq-go` is on the shared tooling list as `yq`. The agent-defaults says: "Prefer these repo-managed tools over generic fallbacks when they fit the task: … `jq`/`yq`/`dasel` for structured data". Use yq when you'd reach for jq but the input is YAML.

> Note: This is **mikefarah/yq** (Go, jq-compatible syntax), NOT kislyuk/yq (Python wrapper). The two have *different* CLI surfaces; commands here only apply to mikefarah's version.

## Quick Reference

```bash
# Pretty-print or validate
yq . file.yaml
yq -e . file.yaml    # exits non-zero if input isn't valid

# Field access
yq '.foo.bar' file.yaml
yq '.foo.bar // "default"' file.yaml

# Filter list members
yq '.items[] | select(.enabled == true)' file.yaml

# Format conversion (one of yq's headline features)
yq -o json . file.yaml         # YAML → JSON
yq -p json -o yaml . file.json # JSON → YAML
yq -o toml . file.yaml         # YAML → TOML

# In-place edit (yq supports it natively, unlike jq)
yq -i '.app.port = 8080' file.yaml
yq -i 'del(.app.tls)' file.yaml

# Build YAML from scratch
yq -n '{"app": {"name": "demo", "port": 8080}}'
```

## Project Context

This repo's [chezmoi/.chezmoiexternal.toml.tmpl](../../../chezmoi/.chezmoiexternal.toml.tmpl) is TOML, but [.sops.yaml](../../../.sops.yaml), [.gitleaks.toml](../../../.gitleaks.toml), [taskfile.yaml](../../../taskfile.yaml), and various GitHub workflows under [.github/workflows/](../../../.github/workflows/) are YAML. Use yq when scripting changes against those.

For converting between TOML and YAML, `dasel` is also a good choice — see the [dasel](../dasel/SKILL.md) skill. Pick yq when the task is YAML-heavy with jq-style transforms; pick dasel when it's a simple cross-format read or per-file conversion.

## Differences from jq

Mostly identical filter syntax, with a few adjustments:

| Concept | jq | yq |
|---|---|---|
| In-place edit | manual `tmp+mv` | `-i` flag |
| Output format | only JSON | `-o yaml/json/toml/xml/csv/tsv/props` |
| Input format | only JSON | `-p yaml` (default) `/json/toml/xml/csv/tsv/props` |
| Multi-doc YAML | n/a | `eval-all` subcommand or `... | select(...)` per doc |
| Deep set | `.a.b.c = "x"` | identical |
| Slurp | `-s` | `eval-all` (different model) |

## Common Idioms

### Convert with format change

```bash
yq -p json -o yaml '.' settings.json > settings.yaml
```

### Update a key in place across multiple files

```bash
for f in .github/workflows/*.yml; do
  yq -i '.jobs.test.runs-on = "ubuntu-latest"' "$f"
done
```

### Extract one section across multi-document YAML

```bash
yq eval-all 'select(.kind == "Deployment") | .spec.replicas' manifest.yaml
```

### Drift detection

```bash
current=$(yq -r '.app.port' file.yaml)
if [ "$current" != "$desired" ]; then
  yq -i ".app.port = $desired" file.yaml
fi
```

### Pipe yq output into jq

```bash
yq -o json . config.yaml | jq '.services | keys'
```

## Flags Worth Knowing

| Flag | Meaning |
|---|---|
| `-i` | Write changes back to the input file |
| `-p F` | Input format (`yaml`/`json`/`toml`/`xml`/`csv`/`tsv`/`props`) |
| `-o F` | Output format (same set, plus `shell`) |
| `-r` | Raw output (no quotes) |
| `-e` | Exit non-zero on null/false output |
| `-n` | Null input (for building from scratch) |
| `-N` | Suppress doc separator on multi-doc YAML output |
| `-I N` | Indent N spaces (default 2) |
| `--front-matter F` | Process YAML frontmatter blocks in markdown |

## References

- `references/help.txt` — captured `yq --help` (yq v4.50.1).
- Project: <https://github.com/mikefarah/yq>.
- Manual / cookbook: <https://mikefarah.gitbook.io/yq/>.

## Notes

- `yq -i` mutates the file's formatting (re-emits as canonical YAML), which can cause noisy diffs on whitespace-sensitive files. Inspect with `git diff` before committing.
- For YAML files with comments worth preserving, use `--no-doc` and `-P` flags carefully — yq's preserve-comments mode is on by default but doesn't always survive structural edits.
- `eval-all` (alias `ea`) loads ALL inputs into memory; for large multi-doc streams prefer `eval` (`e`, the default) which processes one doc at a time.
- For pure JSON work, jq has a more mature ecosystem of recipes; convert to JSON via `yq -o json` and pipe to jq when the recipe is JSON-specific.
