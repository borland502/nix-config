---
name: gum
description: gum — interactive shell prompts for scripts (choose, confirm, input, filter, spin, table, write). Use when writing shell scripts that need user selection, confirmation dialogs, styled output, or progress spinners without a full TUI framework.
---

# gum

`gum` provides styled, interactive UI components for shell scripts: menus, confirmations, text input, filtering, spinners, and more. It is a sibling to `fzf` — prefer `fzf` for fuzzy file/line search; prefer `gum` for structured prompts and styled output in scripts.

## Commands at a Glance

| Command | Purpose |
|---|---|
| `gum choose` | Pick one item from a list |
| `gum filter` | Fuzzy-filter a list (like fzf, but styled) |
| `gum confirm` | Yes/No confirmation prompt |
| `gum input` | Single-line text input |
| `gum write` | Multi-line text input |
| `gum spin` | Spinner while a command runs |
| `gum style` | Apply colors/borders/padding to text |
| `gum table` | Render CSV/TSV as a formatted table |
| `gum file` | File picker |
| `gum pager` | Scrollable pager for text |
| `gum log` | Styled log output (info/warn/error) |
| `gum format` | Render markdown or template strings |

## Examples

### Choose

```bash
# Single selection from a list
BRANCH=$(git branch --list | sed 's/*//' | gum choose)
git checkout "$BRANCH"

# Multi-select (space to select, enter to confirm)
FILES=$(ls | gum choose --no-limit)

# Custom header
ENV=$(echo -e "dev\nstaging\nprod" | gum choose --header "Deploy to:")
```

### Filter (fuzzy)

```bash
# Fuzzy-filter stdin
CONTAINER=$(docker ps --format '{{.Names}}' | gum filter --placeholder "container...")
```

### Confirm

```bash
gum confirm "Delete all .tmp files?" && find . -name '*.tmp' -delete
```

### Input

```bash
NAME=$(gum input --placeholder "Enter your name")
TOKEN=$(gum input --password --placeholder "API token")
```

### Write (multi-line)

```bash
BODY=$(gum write --placeholder "Commit message body...")
git commit -m "$(gum input --placeholder 'Subject')" -m "$BODY"
```

### Spin

```bash
# Show a spinner while a command runs; output is suppressed during spin
gum spin --spinner dot --title "Building..." -- make build

# Capture output
OUTPUT=$(gum spin --spinner line --title "Fetching..." -- curl -s https://api.example.com)
```

### Style

```bash
# Print a styled header
gum style --foreground 212 --bold --border rounded --padding "1 2" "Deployment Complete"

# Combine with log
gum log --level info "Server started on port 8080"
gum log --level warn "Config file not found, using defaults"
gum log --level error "Connection refused"
```

### Table

```bash
# Render a CSV as a table
echo "Name,Age,Role\nAlice,30,Engineer\nBob,25,Designer" | gum table
```

## Best Practices

- Exit codes: `gum confirm` exits 0 for Yes, 1 for No — use with `&&` or `if`.
- `gum choose --no-limit` allows multi-select; result is newline-separated.
- Use `gum spin -- <cmd>` to keep a spinner visible while hiding command output from TTY.
- `gum style` is composable — pipe one styled string into another for layered formatting.
- For non-interactive / CI contexts, check `[ -t 0 ]` (stdin is a TTY) before calling gum to avoid hanging scripts.
