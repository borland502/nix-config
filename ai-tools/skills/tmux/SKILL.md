---
name: tmux
description: tmux — terminal multiplexer for persistent sessions, split panes, and window management. Use when running long jobs that must survive disconnects, splitting the terminal for side-by-side work, or managing multiple shell contexts in one window.
---

# tmux

tmux is a terminal multiplexer: one terminal can host many sessions, each with multiple windows, each split into multiple panes. Sessions persist after disconnects.

## Core Concepts

| Term | Meaning |
|---|---|
| **Session** | Top-level container; survives terminal close. Named or numbered. |
| **Window** | A tab inside a session; fills the full terminal. |
| **Pane** | A split region inside a window. |

Default prefix key: `Ctrl-b` (shown as `<prefix>` below).

## Session Management

```bash
# Start a new named session
tmux new-session -s work

# Attach to an existing session
tmux attach -t work
# or shorthand
tmux a -t work

# List sessions
tmux ls

# Detach from current session (inside tmux)
# <prefix> d

# Kill a session
tmux kill-session -t work

# Kill all sessions
tmux kill-server
```

## Window Management (inside tmux)

```
<prefix> c        New window
<prefix> ,        Rename current window
<prefix> w        Interactive window list
<prefix> n / p    Next / previous window
<prefix> <N>      Jump to window N (0-9)
<prefix> &        Kill current window (with confirmation)
```

## Pane Management (inside tmux)

```
<prefix> %        Split horizontally (left/right)
<prefix> "        Split vertically (top/bottom)
<prefix> <arrow>  Move between panes
<prefix> z        Zoom / unzoom current pane (toggle full-screen)
<prefix> {  }     Swap pane with previous / next
<prefix> x        Kill current pane (with confirmation)
<prefix> q        Show pane numbers briefly; type number to jump
```

## Resize Panes

```
<prefix> :resize-pane -D 5    Grow down 5 lines
<prefix> :resize-pane -U 5    Grow up 5 lines
<prefix> :resize-pane -L 10   Grow left 10 cols
<prefix> :resize-pane -R 10   Grow right 10 cols
```

## Copy Mode (scrollback)

```
<prefix> [        Enter copy mode (scroll with arrow keys / PgUp/PgDn)
<prefix> ]        Paste buffer
q                 Exit copy mode
```

## Run Commands Non-Interactively

```bash
# Run a command in a new detached session
tmux new-session -d -s build -x 220 -y 50 'make all'

# Send keys to a running session's pane
tmux send-keys -t work 'git status' Enter

# Capture pane output to stdout
tmux capture-pane -t work -p

# Check if a session exists
tmux has-session -t work 2>/dev/null && echo "running"
```

## Common Patterns

```bash
# Start or attach to a session (idempotent)
tmux new-session -A -s main

# Split and run a watcher alongside main work
tmux split-window -h 'task watch'

# Rename window to match the project
tmux rename-window -t main:0 'editor'
```

## Best Practices

- Name sessions after the project, not the task — sessions last longer than individual commands.
- Use `tmux new-session -A -s <name>` to attach if exists, create if not.
- Keep pane splits shallow (2-3 panes per window); use windows for separate concerns.
- For long-running background jobs, detach with `<prefix> d` rather than leaving a terminal open.
- `tmux kill-server` nukes everything; prefer `kill-session` for surgical cleanup.
