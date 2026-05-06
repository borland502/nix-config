---
name: fd
description: Use when finding files or directories by name, type, or attributes. fd is the project's preferred find replacement — gitignore-aware, regex by default, parallel, and friendlier syntax. Covers the patterns this repo uses (locate by extension, run a command per match, exclude paths, fd-then-rg pipelines).
---

# fd

`fd` is on the shared tooling list and is the project's default file finder. The agent-defaults explicitly says: "Prefer these repo-managed tools over generic fallbacks when they fit the task: … `fd` over `find`".

## Quick Reference

```bash
# Find by name (regex by default)
fd 'pattern'
fd '\.toml$' chezmoi/

# Glob mode (literal patterns + shell globs)
fd -g '*.nix' home-manager/

# Restrict to file types
fd -t f 'pattern'   # files only
fd -t d 'pattern'   # directories only
fd -t l 'pattern'   # symlinks
fd -t x              # executables (bare type → all matches)

# Filter by extension shorthand
fd -e nix
fd -e md -e mdx

# Search hidden / no-ignore (defaults respect .gitignore + .ignore)
fd --hidden 'pattern'
fd --no-ignore --hidden 'pattern'

# Limit depth
fd -d 2 'pattern'
fd --max-depth 3 'pattern'

# Print absolute paths
fd -a 'pattern'

# Run a command per match
fd -e py --exec python -m py_compile {}
fd -e nix -X alejandra        # batched (single invocation with all paths)

# Print + count combo
fd -t f | wc -l
```

## Project Context

This repo's [home-manager/local/bin/cache-scan.sh](../../../home-manager/local/bin/cache-scan.sh) uses `fd` to scan timestamped log files under `~/.cache/copilot/`. It's the canonical example of "list by recency" in this project.

Several places in the codebase iterate `find ... -type d` (e.g. for chezmoi-related discovery) where `fd -t d` would read more cleanly. Existing usage is left as-is unless the surrounding code is being touched.

## Common Idioms

### Find all SKILL.md across upstream repos

```bash
fd -t f SKILL.md ~/.local/src/ai-tools/
```

### List directories containing a SKILL.md (jump-list candidates)

```bash
fd -t f --max-depth 4 SKILL.md ~/.local/src/ai-tools/ | xargs -n1 dirname
```

### fd → rg pipeline (find then content-search)

```bash
fd -e py | xargs rg "import requests"
```

### Open every match in $EDITOR

```bash
fd -e nix --exec $EDITOR
```

### Format every changed-since-main nix file

```bash
git diff --name-only main...HEAD | rg '\.nix$' | xargs alejandra
# or:
fd -e nix --changed-after main --exec alejandra
```

(`--changed-after` works against git refs in fd 8.4+.)

### Exclude a path (e.g. node_modules) explicitly

```bash
fd 'pattern' -E 'node_modules' -E '.direnv'
```

(`.gitignore` already excludes these in this repo, but `-E` is useful when searching outside the repo.)

### Type-and-mtime combo

```bash
fd -t f -e log --changed-within 1d ~/.cache/copilot/
```

## Flags Worth Knowing

| Flag | Meaning |
|---|---|
| `-t T` | Filter by type: `f` file, `d` directory, `l` symlink, `x` executable, `e` empty, `s` socket, `p` pipe |
| `-e EXT` | Filter by extension (no leading dot; repeatable) |
| `-E PATTERN` | Exclude pattern (gitignore-style) |
| `-g` | Glob mode (otherwise pattern is regex) |
| `-i` / `-s` | Case-insensitive / sensitive |
| `-H` / `--hidden` | Include dotfiles |
| `-I` / `--no-ignore` | Ignore .gitignore + .ignore + .fdignore |
| `-d N` | Max depth |
| `--min-depth N` | Min depth |
| `-a` | Print absolute paths |
| `-0` | Null-terminator separator (for `xargs -0`) |
| `--exec CMD` | Run command per match (`{}` is the path; `{.}` no extension; `{/}` basename; `{//}` parent) |
| `--exec-batch CMD` / `-X` | Run command once with all matches as args |
| `--changed-within DUR` | Filter by mtime within last duration (`1d`, `2h`, `30s`) |
| `--changed-before DUR` | Inverse of above |
| `--owner USER:GROUP` | Filter by file owner |
| `--size SPEC` | Filter by size (`+1M`, `-100k`) |

## Pitfalls

- **fd respects .gitignore by default**, like rg. Outside-the-repo searches behave normally; inside-the-repo searches skip ignored paths. Use `--no-ignore` to override.
- **Regex by default, not glob.** `fd .nix` matches anything containing `n`, `i`, `x` because `.` is "any char". Use `-g '*.nix'` for shell-glob semantics, or `-e nix`.
- **`--exec` runs per match** — for tools where startup is expensive (alejandra, statix), prefer `--exec-batch`/`-X`.
- **`{}` placeholder is implicit** if `--exec`'s command takes only one arg: `fd -e nix --exec alejandra` is equivalent to `... --exec alejandra '{}'`.

## References

- `references/help-short.txt` — captured `fd -h` (concise help).
- `references/help-full.txt` — captured `fd --help` (full help).
- README: <https://github.com/sharkdp/fd>.
- Tutorial: <https://github.com/sharkdp/fd#tutorial>.
