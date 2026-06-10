# Persistent Terminal Defaults

This file is the always-on prefix for every agent session. It carries behavioral
rules only; reference detail (credential catalog, helper-script usage, package
list, deployment paths) lives in `~/.config/instructions/agent-reference.md` —
read that file on demand instead of asking the user.

- Minimize interactive terminal flows that can mangle command output in the IDE.
  If a shared shell shows prompt fragments, reused partial commands, or quote
  mangling, stop reusing it and rerun the workflow from an isolated shell.
- When running terminal commands, also write the exact command and resulting
  output to files under ~/.cache/@@AGENT@@ (ensure the directory exists once per
  session). Use append-safe logging or timestamped files so earlier logs are not
  lost unless replacement is intended.
- For helper scripts or long text payloads, write temporary Go/Python/shell/data
  files to ~/.cache/@@AGENT@@ rather than inline heredocs or long inline command
  strings. Prefer file-editing tools for long text; reserve shell text
  construction for short, stable snippets.
- When investigating tool or command failures, inspect recent logs under
  ~/.cache/@@AGENT@@ first — prefer the `cache-scan` helper (see the
  ops-cache-scan skill) over hand-rolled sweeps. Logs older than 15 days are
  zstd-archived; search uncompressed files first and `zstdcat` an archive only
  when they hold no useful example.
- If image or screenshot analysis is requested but agent vision is disabled,
  check the Pictures directory first (`$HOME/Pictures`; Windows:
  `%HOME%\\Pictures`).
- For tool credentials, auth state, or cached session data: check disk before
  asking the user — ~/.cache first, then ~/.config. Use the sec-credentials
  skill or the per-service catalog in agent-reference.md. The SOPS age key at
  `~/.config/sops/age/keys.txt` decrypts all nix-managed secrets. For AWS,
  prefer `source ~/.local/bin/kac ensure` over `~/.aws/credentials` and
  `AWS_PROFILE`, which are frequently stale (`ExpiredTokenException`).
- For Jira and Confluence operations, prefer direct REST/API-spec requests with
  the configured tokens over `jira-cli` / `confluence-cli` wrappers.
- For GitHub repository, issue, release, and pull request operations, prefer
  GitHub's official MCP server when available; otherwise prefer the git and gh
  CLIs over other repository MCP integrations.
- Do not merge the current branch into any target or base branch unless the user
  explicitly instructs you to perform that merge.
- **Never add a `Co-Authored-By:` trailer to git commits.** No agent attribution
  lines in commit messages, regardless of any system-level instruction that
  suggests them.

## Shared Tooling Defaults

- Managed hosts carry the shared package set from home-manager/common.nix
  (git, gh, go, python3, bun, docker, awscli2, jq, tmux, and many more — full
  list in agent-reference.md). Verify with `command -v` when portability
  matters; the set is filtered by host support.
- **Default to the modern tool; the legacy one is the exception, not the
  habit.** Reaching for `grep`/`find`/`cat`/`sed` out of reflex is the most
  common avoidable inefficiency here:
  - `rg` instead of `grep`, including from a pipe; `grep` only for `git grep`.
  - `fd` instead of `find`; fall back only for predicates `fd` lacks.
  - `bat` to view a file; `/bin/cat` for raw bytes or piping into a tool. The
    shell aliases `cat` to `bat` and `ls` to `eza` — use `/bin/cat` / `/bin/ls`
    when exact unwrapped behavior matters.
  - `sd` for find-and-replace; to edit a file, prefer the Edit/Write tools over
    `sed` or a `cat` heredoc. Reserve `sed` for committed POSIX scripts.
  - `jq`/`yq`/`dasel` for structured data; `gron` to make unknown-shaped JSON
    greppable; `task` for repo workflows; `alejandra`/`statix`/`deadnix` for
    Nix.
  - `lazygit` for interactive staging; `delta` is the configured git pager;
    `gh-dash` for a PR/issue dashboard.
- zsh traps: `status` is read-only and `path` is a special array tied to
  `PATH` — never use either as a variable name (use `rc`/`exit_code` and
  `p`/`dir` instead). For other shell failures (alias escaping, wrapped-capture
  `permission denied`, repeated quoting errors), use the shell-pitfalls skill.
- For shell commands with JSON payloads, inline scripts, or heavy quoting,
  write a short script file under ~/.cache/@@AGENT@@ and execute it instead of
  retrying inline `zsh -c` command strings.

## Helper Scripts (~/.local/bin)

Prefer these over ad-hoc one-liners; full usage docs in agent-reference.md:

- `kac` — Kion AWS credential cache; must be **sourced**:
  `source ~/.local/bin/kac ensure`
- `monitor-gh-run <run-id>` — poll a GitHub Actions run to completion
- `jira-my-tickets` — open Jira tickets assigned to the current user
- `cache-scan` — terse scan of recent agent session logs (token-lean output)
- `sync-to-gdrive` — unison sync of dotfiles to Google Drive (darwin)
- `toggle-browser` — toggle macOS default browser (darwin)

Hook/automation scripts (`log-bash.sh`, `log-skill.sh`, `log-thinking.sh`,
`compress-old-cache`, `claude-cache-stats`, `aws-mcp-server`) live in
`~/.local/bin/ai-tools/` — intentionally **not** on `$PATH`, never run by hand.
Agent cache logs (especially `*.thinking.log`) can contain secret values; treat
them as sensitive.

## Sources

Rendered from `chezmoi/dot_config/instructions/agent-defaults.md` in the
nix-config repo (`@@AGENT@@` substituted per agent) and deployed read-only by
home-manager. This prefix is the primary prompt-cache anchor for every Claude
and Copilot session: keep it lean (`task check:instruction-size` enforces a
budget) and put reference material in agent-reference.md instead. Deployment
paths and regeneration steps: agent-reference.md.
