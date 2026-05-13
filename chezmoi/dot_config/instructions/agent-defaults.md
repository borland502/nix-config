# Persistent Terminal Defaults

- Minimize use of interactive terminal flows that can mangle command output in the IDE.
- If a shared shell shows prompt fragments, reused partial commands, or quote mangling,
  stop reusing it and rerun the workflow from an isolated shell.
- When running terminal commands, also write the exact command and the resulting
  output to files under ~/.cache/@@AGENT@@.
- Ensure ~/.cache/@@AGENT@@ exists once per session before attempting to write
  logs there.
- For helper scripts or long text payloads, write temporary Go, Python, shell, or
  data files to ~/.cache/@@AGENT@@. Prefer this over inline heredocs or long
  inline command strings.
- Prefer file-editing tools for long text whenever possible; reserve shell text
  construction for short, stable snippets.
- Use append-safe logging or timestamped files so earlier command logs are not
  lost unless replacement is explicitly intended.
- When investigating tool or command failures, inspect relevant logs under
  ~/.cache/@@AGENT@@ first; use prior successful executions there as concrete
  examples before retrying or changing approach. Cache files are archived as
  `.zst` (Zstandard) by a Stop hook when older than 30 days or larger than 10
  MB. Search uncompressed files first. If no useful example is found, locate the
  relevant `.zst` archives and decompress on the fly with `zstdcat <file>` via
  Bash before reading. Do not decompress speculatively; only decompress when
  uncompressed logs contain no useful example.
- When looking for tool credentials, auth state, or cached session data, examine
  ~/.cache first and then ~/.config. Known locations by service:
  - **Jira**: token at `~/.config/ops-agent/jira-token`, base URL at
    `~/.config/ops-agent/jira-base-url` (SOPS-decrypted from
    `secrets/ops-agent.yaml` in the nix-config repo)
  - **Confluence**: token at `~/.config/confluence/token`, base URL at
    `~/.config/confluence/base-url` (same SOPS source)
  - **AWS**: `~/.aws/config` and `~/.aws/credentials`; Kion session cache at
    `~/.cache/kion-aws-cache/`
  - **GitHub (gh CLI)**: `~/.config/gh/hosts.yml`
  - **SOPS age key** (decrypts all nix-managed secrets):
    `~/.config/sops/age/keys.txt`
- For Jira and Confluence operations, prefer direct REST/API-spec requests with
  configured tokens over dedicated `jira-cli` or `confluence-cli` wrappers.
- For GitHub repository, issue, release, and pull request operations, prefer
  GitHub's official MCP server when it is available.
- When GitHub's official MCP server is unavailable, prefer the git CLI and gh
  CLI over other repository MCP integrations.
- Do not merge the current branch into any target or base branch unless the user
  explicitly instructs you to perform that merge.

## Shared Tooling Defaults

- The shared package set in home-manager/common.nix usually provides these CLI
  tools on managed hosts: git, gh, curl, wget, gcc, go, gopls, govulncheck,
  delve (`dlv`), go-task (`task`), pkg-config, python3, pipx, maven, awscli2,
  awslogs, aws-sam-cli, checkov, bun, docker, docker-buildx, docker-compose,
  overmind, bat, eza, fzf, fd, ripgrep (`rg`), sd, jq, yq-go (`yq`), zoxide,
  direnv, dasel, tmux, age, zstd, unzip, p7zip (`7z`/`7za`/`7zr`), alejandra,
  ncdu, statix, deadnix, nixd, markdownlint-cli2, ruff, shellcheck, shfmt,
  yamllint, taplo, unison, glow, gum, tealdeer, scrcpy, cowsay, file, which,
  tree, rsync, btop, and lsof.
- Prefer these repo-managed tools over generic fallbacks when they fit the task:
  `rg` over `grep`, `fd` over `find`, `jq`/`yq`/`dasel` for structured data,
  `task` for repository workflows, and `alejandra`/`statix`/`deadnix` for Nix
  formatting and linting.
- Treat this tool list as the default expected environment for repo work, but
  verify availability with `command -v` when portability matters because
  home-manager/common.nix still filters packages by host support.
- Shell aliases `ls` to `eza`; use `/bin/ls` when exact BSD `ls` flags or output
  ordering matter.
- In zsh wrappers, avoid `status` as a shell variable name; it is read-only. Use
  `rc` or `exit_code` instead.
- Shell may alias `cat` to `bat`; use `/bin/cat` when you need raw file contents
  without pager/formatting behavior.
- If a cache-path script shows `permission denied` only inside a wrapped capture
  command, retry with a direct `/bin/zsh -f <script>` invocation before assuming
  file permissions are the issue.
- For shell commands with JSON payloads, inline scripts, or heavily quoted
  objects, prefer writing a short script file under ~/.cache/copilot and
  executing that file instead of retrying inline `zsh -c` command strings.

## Agent Instruction Sources

This file (`chezmoi/dot_config/instructions/agent-defaults.md`) is the single
source of truth for persistent agent defaults. It is rendered by
`home-manager/lib/agent-instructions.nix` (substituting `@@AGENT@@` with the
agent name) and deployed as read-only symlinks via home-manager. Each deployed
file is loaded into the agent session's system prompt at startup and is the
primary source of Anthropic prompt-cache hits for that session.

Stable deployment paths — these symlinks always point to the active generation:

**Claude** (loaded via `CLAUDE_CONFIG_DIR` or fallback):

- `~/.config/claude/CLAUDE.md` — primary
- `~/.claude/CLAUDE.md` — fallback / memory resolution path

**Copilot:**

- `~/.config/github-copilot/copilot-defaults.instructions.md` — Copilot CLI
- `~/Library/Application Support/Code/User/prompts/copilot-defaults.instructions.md` — VS Code stable (macOS)
- `~/Library/Application Support/Code - Insiders/User/prompts/copilot-defaults.instructions.md` — VS Code Insiders (macOS)
- `~/.config/Code/User/prompts/copilot-defaults.instructions.md` — VS Code (Linux/XDG)
- `~/.vscode-server/data/User/prompts/copilot-defaults.instructions.md` — VS Code Server

Each symlink resolves through the current home-manager generation bundle in the
nix store. To find the active nix store path for a given agent:

```sh
readlink -f ~/.config/claude/CLAUDE.md          # Claude variant
readlink -f ~/.config/github-copilot/copilot-defaults.instructions.md  # Copilot variant
```

The chezmoi path for this file (`chezmoi/dot_config/instructions/`) makes the
credential and cache-directory locations documented above discoverable on hosts
that have chezmoi but not the full nix config.
