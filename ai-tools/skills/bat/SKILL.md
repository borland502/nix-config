---
name: bat
description: bat — syntax-highlighted cat replacement with Git integration, diff view, line ranges, and plain-output mode for piping. Use when reading files with context, diffing against Git index, or passing highlighted output to a pager.
---

# bat

`bat` is a `cat` clone with syntax highlighting, Git integration, and a built-in pager. The shell may alias `cat` to `bat`; use `/bin/cat` when you need raw output without decorations.

## When to Use

- Reading source files with syntax highlighting and line numbers in the terminal.
- Showing only lines changed relative to the Git index (`--diff`).
- Highlighting a specific line range during code review or debugging.
- Piping content to another tool — use `-p` / `--plain` to strip decorations.
- Forcing a language when the extension is ambiguous or piping from stdin.

## Key Flags

| Flag | Effect |
|---|---|
| `-p` / `--plain` | Strip all decorations (line numbers, grid, header). Use for piping. |
| `-pp` | Also disables automatic paging (`--paging=never`). |
| `-l <lang>` | Force syntax language (e.g. `-l json`, `-l yaml`, `-l md`). |
| `-H <N:M>` | Highlight line range with a background color. |
| `-d` / `--diff` | Show only added/removed/modified lines (Git diff mode). |
| `--diff-context=N` | Lines of context around diff hunks (default 2). |
| `--file-name <name>` | Set display name for stdin; also drives syntax detection. |
| `-A` / `--show-all` | Show non-printable characters (spaces, tabs, newlines). |
| `--paging=never` | Disable pager unconditionally. |

## Examples

```bash
# Read a file with syntax highlighting
bat src/main.rs

# Highlight lines 40-55 while reading
bat -H 40:55 src/main.rs

# Show only Git-modified lines with 5 lines of context
bat --diff --diff-context=5 src/main.rs

# Pipe JSON from a command with syntax highlighting
curl -s https://api.example.com/data | bat -l json

# Strip all decorations for use in a script
bat -pp config.yaml | grep "key:"

# Read stdin with an explicit filename for syntax detection
cat unknown_file | bat --file-name=config.toml

# Show non-printable characters to debug whitespace issues
bat -A Makefile
```

## Best Practices

- Use `bat -pp` (not just `-p`) when piping into tools that are sensitive to pager output — `-pp` also disables the pager.
- Set `BAT_THEME` in your environment to override the default theme globally; or pass `--theme` per invocation.
- `bat --list-languages` shows all recognized language names and extensions.
- `bat --list-themes` lists available themes.
- When `cat` is aliased to `bat`, use `/bin/cat` in scripts that must not produce decorations.
