---
description: "Use for every task. Persistent defaults for terminal commands, shell usage, and command logging. Prefer non-interactive commands and log command plus output to ~/.cache/copilot."
name: "Persistent Terminal Logging Defaults"
applyTo: "**"
---

# Persistent Terminal Defaults

- Prefer non-interactive commands over interactive shells unless the task explicitly requires an interactive program.
- Minimize use of interactive terminal flows that can mangle command output in the IDE.
- When running terminal commands, also write the exact command and the resulting output to files under ~/.cache/copilot.
- Ensure ~/.cache/copilot exists before attempting to write logs there.
- Prefer executing scripts from files written under ~/.cache/copilot instead of inline heredocs when a command needs multi-line shell logic.
- Use append-safe logging or timestamped files so earlier command logs are not lost unless replacement is explicitly intended.
- When investigating tool or command failures, inspect relevant logs under ~/.cache/copilot first; use prior successful executions there as concrete examples before retrying or changing approach.
- Do not use GitKraken MCP tools for private repositories.
- For public repositories, prefer the git CLI and gh CLI over GitKraken MCP tools unless the user explicitly asks for GitKraken.
- Do not merge the current branch into any target or base branch unless the user explicitly instructs you to perform that merge.

# Shared Tooling Defaults

- The shared package set in home-manager/common.nix usually provides these CLI tools on managed hosts: git, gh, curl, wget, go-task (`task`), python3, pipx, maven, awscli2, awslogs, aws-sam-cli, checkov, bun, docker, docker-buildx, docker-compose, overmind, bat, eza, fzf, fd, ripgrep (`rg`), sd, jq, yq-go (`yq`), zoxide, direnv, dasel, tmux, unzip, p7zip (`7z`/`7za`/`7zr`), age, alejandra, ncdu, statix, deadnix, nixd, unison, glow, gum, tealdeer, file, which, tree, and rsync.
- Prefer these repo-managed tools over generic fallbacks when they fit the task: `rg` over `grep`, `fd` over `find`, `jq`/`yq`/`dasel` for structured data, `task` for repository workflows, and `alejandra`/`statix`/`deadnix` for Nix formatting and linting.
- Treat this tool list as the default expected environment for repo work, but verify availability with `command -v` when portability matters because home-manager/common.nix still filters packages by host support.
