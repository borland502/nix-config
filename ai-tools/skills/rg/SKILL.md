---
name: rg
description: Use when searching file contents recursively across a tree. ripgrep (rg) is the project's preferred grep replacement — it's gitignore-aware, fast, and supports PCRE2. Covers the patterns this repo uses (find references before refactor, scope by file type, multiline matches) plus pitfalls around the eza/ls alias and quoting.
---

# rg (ripgrep)

`rg` is on the shared tooling list and is the project's default grep. The agent-defaults explicitly says: "Prefer these repo-managed tools over generic fallbacks when they fit the task: `rg` over `grep`".

## Quick Reference

```bash
# Recursive search (the default — no need for -r)
rg "pattern"
rg "pattern" path/

# List matching files only (no line content)
rg -l "pattern"
rg --files-with-matches "pattern"

# Show only the matching part (for capturing)
rg -o "v\d+\.\d+\.\d+"

# Count matches per file
rg -c "TODO"

# Scope by file type (rg --type-list to see all)
rg --type sh "set -euo pipefail"
rg -t nix "homeDirectory"
rg -tpy "import requests"

# Or by glob (negation with !)
rg -g "*.toml" "version"
rg -g "!**/node_modules/**" "react"

# Case-insensitive / smart-case
rg -i "claude"
rg -S "Claude"   # case-sensitive iff pattern has uppercase

# Fixed-string (no regex)
rg -F "$.foo.bar"

# Multiline (across newlines)
rg -U "function\s*\{[^}]*return"

# Context lines
rg -B 2 -A 5 "panic"
rg -C 3 "panic"

# Show line numbers always (for piping or copy-paste)
rg -n "..."

# Replace (preview only — rg never writes; pipe to sd or sed for in-place)
rg "foo" --replace "bar"
```

## Project Context

This repo's [home-manager/local/bin/cache-scan.sh](../../../home-manager/local/bin/cache-scan.sh) uses `rg` to scan `~/.cache/copilot/` logs for failure signatures and command sequences — it's the canonical example of "find by content fast" in this project.

The pre-commit hook in [.githooks/](../../../.githooks/) doesn't use rg directly, but `task lint:nix` shells out to `statix` and `deadnix` which respect similar gitignore behavior.

## Common Idioms

### Find every reference to a symbol before renaming

```bash
rg -nF "CLAUDE_CONFIG_DIR"
rg -lF "CLAUDE_CONFIG_DIR"   # files only — feed to next command
```

### Search only changed files (vs main)

```bash
git diff --name-only main...HEAD | xargs rg "TODO"
```

### Find files NOT containing a pattern

```bash
rg --files-without-match "License" -t md
```

### Locate a JSON key in a tree of mixed-format files

```bash
rg -t json '"refreshPeriod"'
```

### Find then sd-replace (rg + sd)

```bash
rg -l "old-name" | xargs sd "old-name" "new-name"
```

### Pretty output for piped consumption

```bash
rg --json "pattern" | jq '.data | select(.type == "match")'
```

## Flags Worth Knowing

| Flag | Meaning |
|---|---|
| `-l` | Print matching files only |
| `-c` | Print match count per file |
| `-n` / `-N` | Show / suppress line numbers |
| `-o` | Print only matched parts |
| `-i` | Case-insensitive |
| `-S` | Smart case (case-insensitive unless pattern has uppercase) |
| `-F` | Fixed-string match (no regex) |
| `-U` | Multiline (allow `.` to match newlines with `-P` or `--multiline-dotall`) |
| `-P` | PCRE2 regex (lookarounds, backreferences) |
| `-w` | Word-boundary match |
| `-v` | Invert match |
| `-A N` / `-B N` / `-C N` | Trailing / leading / both context lines |
| `-t T` / `-T T` | Include / exclude file type |
| `-g 'glob'` | Include matching glob (negate with `!`) |
| `--files` | Print file list rg WOULD search (no pattern) |
| `--hidden` | Include dotfiles (still respects .gitignore unless `--no-ignore`) |
| `--no-ignore` | Ignore .gitignore (and ripgrep's own ignore files) |
| `--json` | One JSON event per match |

## Pitfalls

- **`ls` is aliased to `eza`** in this project's zsh — but `rg` is not aliased to anything. Plain `rg` works as documented.
- **`grep`-style flag order matters less in rg**, but `--` is still useful when patterns start with `-`: `rg -- "-flag-name"`.
- **rg respects `.gitignore`** by default. To search everything (e.g. `node_modules`, `.git`, etc.) use `--no-ignore --hidden`. The chezmoi externals at `~/.local/src/ai-tools/*` ARE outside the repo, so `rg` from the repo root won't see them — `cd` first or pass an explicit path.
- **PCRE2 isn't on by default**. For lookbehinds/lookaheads use `-P`.
- **rg doesn't do replace-in-place**. Use it to find files, then pipe to `sd` (preferred) or `sed -i` for the actual rewrite.

## References

- `references/help-short.txt` — captured `rg -h` (one-page help).
- `references/help-full.txt` — captured `rg --help` (full reference, ~1600 lines).
- User guide: <https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md>.
- Regex syntax: `rg --regex-help` or <https://docs.rs/regex/latest/regex/#syntax>.
- FAQ: <https://github.com/BurntSushi/ripgrep/blob/master/FAQ.md>.
