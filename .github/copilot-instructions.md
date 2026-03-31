# Copilot Defaults

- Prefer non-interactive commands over interactive shells unless the task explicitly requires an interactive program.
- Minimize use of interactive terminal flows that can mangle command output in the IDE.
- Prefer an isolated shell for long, heavily quoted, or stateful commands. Use a fresh terminal session instead of the shared shell when the command includes complex quoting, regexes, JSON, plist data, `osascript`, `jq`, `nix eval --expr`, or several chained steps.
- If a shared shell shows prompt fragments, reused partial commands, or quote mangling, stop reusing it and rerun the workflow from an isolated shell.
- When running terminal commands, also write the exact command and the resulting output to files under `~/.cache/copilot`.
- Ensure `~/.cache/copilot` exists before attempting to write logs there.
- For multi-line shell logic or long text payloads, write a temporary script or data file under `~/.cache/copilot` and execute it from an isolated shell instead of embedding long inline commands or heredocs.
- Prefer file-editing tools for long text whenever possible; reserve shell text construction for short, stable snippets.
- Use append-safe logging or timestamped files so earlier command logs are not lost unless replacement is explicitly intended.
- When investigating tool or command failures, inspect relevant logs under `~/.cache/copilot` first; use prior successful executions there as concrete examples before retrying or changing approach.
- For GitHub repository, issue, release, and pull request operations, prefer GitHub's official MCP server when it is available.
- Do not use GitKraken MCP tools for either private or public repositories.
- When GitHub's official MCP server is unavailable, prefer the git CLI and gh CLI over other repository MCP integrations.
- Do not merge the current branch into any target or base branch unless the user explicitly instructs you to perform that merge.

# Shared Tooling Defaults

- The shared package set in `home-manager/common.nix` usually provides these CLI tools on managed hosts: git, gh, curl, wget, go-task (`task`), python3, pipx, maven, awscli2, awslogs, aws-sam-cli, checkov, bun, docker, docker-buildx, docker-compose, overmind, bat, eza, fzf, fd, ripgrep (`rg`), sd, jq, yq-go (`yq`), zoxide, direnv, dasel, tmux, unzip, p7zip (`7z`/`7za`/`7zr`), age, alejandra, ncdu, statix, deadnix, nixd, unison, glow, gum, tealdeer, file, which, tree, and rsync.
- Prefer these repo-managed tools over generic fallbacks when they fit the task: `rg` over `grep`, `fd` over `find`, `jq`/`yq`/`dasel` for structured data, `task` for repository workflows, and `alejandra`/`statix`/`deadnix` for Nix formatting and linting.
- Treat this tool list as the default expected environment for repo work, but verify availability with `command -v` when portability matters because `home-manager/common.nix` still filters packages by host support.
