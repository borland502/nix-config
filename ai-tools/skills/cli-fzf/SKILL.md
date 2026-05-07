---
name: cli-fzf
description: Use when interactive fuzzy selection from a list is wanted in a shell script (file picker, branch picker, command builder) or when wiring a tool's output into a TUI selector. fzf is on the project's shared tooling list; the zsh integration provides Ctrl-T / Ctrl-R / Alt-C bindings out of the box.
---

# fzf

`fzf` is a general-purpose fuzzy finder. It reads a list on stdin, lets the user filter/select interactively, and prints the selection on stdout. The shell integration (zsh in this project) wires it up to `Ctrl-T`, `Ctrl-R`, and `Alt-C` for file/history/directory selection.

## Quick Reference

```bash
# Pick a file from the current dir
ls | fzf

# Pick a file with rg-style preview (uses bat for syntax highlighting)
fd -t f | fzf --preview 'bat --color=always --line-range=:200 {}'

# Pick a branch and check it out
git branch -a | sd '^[* ] ' '' | fzf | xargs git checkout

# Pick a process to kill
ps -ef | fzf --multi --header-lines=1 | awk '{print $2}' | xargs kill

# Multi-select (TAB to toggle)
fd -e nix | fzf -m | xargs alejandra

# Built-in shell bindings (zsh integration is enabled in this repo):
#   Ctrl-T    Insert selected file path(s) at cursor
#   Ctrl-R    Search shell history
#   Alt-C     cd into a selected directory
#   **<TAB>   Trigger fuzzy completion for the current arg
```

## Project Context

`fzf` is on the shared tooling list in [chezmoi/dot_config/instructions/agent-defaults.md](../../../chezmoi/dot_config/instructions/agent-defaults.md). The zsh setup in [home-manager/zsh.nix](../../../home-manager/zsh.nix) doesn't have an explicit fzf integration block — fzf's zsh keybindings are activated by the `programs.fzf.enableZshIntegration = true` Home Manager option (verify the actual setting; it may be on by default with `programs.fzf.enable`).

For non-interactive scripts, prefer plain pipelines (`rg`, `fd`, `jq`) — fzf is for human-in-the-loop selection only.

## Common Idioms

### Interactive `cd`

```bash
cd "$(fd -t d | fzf --preview 'eza --tree --level=2 {} 2>/dev/null')"
```

### Pick a recent log under ~/.cache/claude

```bash
fd -e log . ~/.cache/claude --changed-within 7d \
  | fzf --preview 'bat --color=always {}' \
  | xargs cat
```

### Branch picker with last-commit preview

```bash
git branch --sort=-committerdate \
  | sd '^[* ] ' '' \
  | fzf --preview 'git log -1 --color=always {}'
```

### Skill picker (jump to a skill's SKILL.md)

```bash
fd SKILL.md ai-tools/skills/ \
  | fzf --preview 'bat --color=always {}' \
  | xargs $EDITOR
```

### Multi-select for batched ops

```bash
git status --porcelain \
  | fzf --multi \
  | awk '{print $2}' \
  | xargs git add
```

### Kill a port-bound process

```bash
lsof -nP -iTCP -sTCP:LISTEN \
  | fzf --header-lines=1 --multi \
  | awk '{print $2}' \
  | xargs kill
```

## Flags Worth Knowing

| Flag | Meaning |
|---|---|
| `-m` / `--multi` | Allow multi-select with TAB |
| `-e` / `--exact` | Exact match instead of fuzzy |
| `-i` / `+i` | Case-insensitive / sensitive (default: smart-case) |
| `--preview CMD` | Side-pane preview; `{}` is the current line |
| `--preview-window W` | Preview position (`right:60%`, `down:30%`, `hidden`) |
| `--header TXT` | Sticky header above results |
| `--header-lines N` | Treat first N input lines as header (kept on screen, not selectable) |
| `--height H` | TUI height (`40%`, `30`); essential when fzf is one of several panes |
| `--reverse` | Layout with prompt at top |
| `--query Q` | Pre-fill the query |
| `--bind KEY:ACTION` | Custom keybindings (e.g. `--bind 'ctrl-y:execute(echo {} | pbcopy)'`) |
| `--ansi` | Honor ANSI color codes from input |
| `-d DELIM` | Field delimiter for `--with-nth` / `--nth` (default: whitespace) |
| `--with-nth N..` | Display only those fields (still match against all) |
| `--nth N..` | Match only against those fields |

## References

- `references/help.txt` — captured `fzf --help` (fzf 0.67.0).
- Project: <https://github.com/junegunn/fzf>.
- Wiki / examples: <https://github.com/junegunn/fzf/wiki/examples>.
- Recipes: <https://github.com/junegunn/fzf/blob/master/ADVANCED.md>.

## Notes

- fzf is interactive — it requires a TTY. In non-TTY contexts (CI, hooks, sub-shells without `--height` against piped input) it will exit with an error. Check `[ -t 0 ]` before invoking, or fall back to `head -1` for first-only behavior.
- The `--preview` command runs once per highlighted line. Heavy commands (e.g. building thumbnails, running git log on large repos) make navigation laggy. Cache or scope previews tightly.
- fzf reads stdin until EOF before showing the UI. For very long lists, use `--height` so partial scrolling works while input streams. Consider `fzf --tail N` to keep only the last N lines.
- The `**<TAB>` completion trigger and the `Ctrl-T` / `Ctrl-R` / `Alt-C` bindings are zsh-shell integrations, NOT fzf-binary features. Fish/bash have their own integration files.
