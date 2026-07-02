# Agent Reference

On-demand companion to `agent-defaults.md` (the always-on prefix). Nothing in
this file loads into the system prompt automatically — agents read it when a
task needs the detail. Deployed by chezmoi to
`~/.config/instructions/agent-reference.md` on every platform; the chezmoi
source path (`chezmoi/dot_config/instructions/`) keeps these locations
discoverable on hosts that have chezmoi but not the full nix config.

## Credential & Auth Locations

Lookup order: `~/.cache` first, then `~/.config`. Known locations by service:

- **Jira**: token at `~/.config/ops-agent/jira-token`, base URL at
  `~/.config/ops-agent/jira-base-url`, email at
  `~/.config/ops-agent/jira-email` (SOPS-decrypted from
  `secrets/ops-agent.yaml` in the nix-config repo)
- **Confluence**: token at `~/.config/confluence/token`, base URL at
  `~/.config/confluence/base-url` (same SOPS source)
- **AWS**: `~/.aws/config` and `~/.aws/credentials`; Kion session cache at
  `~/.cache/kion-aws-cache/`. Credentials in `~/.aws/credentials` and
  `AWS_PROFILE` are frequently stale and produce `ExpiredTokenException`.
  Source `kac` (must be sourced; works from bash or zsh) to load from cache or
  refresh automatically via `gkion` if the cache is stale:

  ```sh
  source ~/.local/bin/kac ensure
  ```

  Do this **before** the first `aws` call, not after one fails, and gate on its
  exit code — for a one-shot, chain both:
  `zsh -lc 'source ~/.local/bin/kac ensure >/dev/null && aws …'`. Do **not**
  `cat` the cache files into `export`s (no freshness guarantee — the observed
  stale-creds anti-pattern; `kac ensure` reads the same files and validates
  them). Do not `aws sso login` or `find`/`zstdcat` for the cache path; `kac`
  owns it.

- **GitHub (gh CLI)**: `~/.config/gh/hosts.yml`
- **SOPS age key** (decrypts all nix-managed secrets):
  `~/.config/sops/age/keys.txt`

## Helper Script Catalog (~/.local/bin)

Utility scripts deployed to `~/.local/bin` (on `$PATH`) by chezmoi. Source
files live in `chezmoi/dot_local/bin/` (and `chezmoi/dot_local/lib/`) within
the nix-config repo.

- **`kac`** — Kion AWS credential cache proxy. Must be **sourced** (not
  executed). Backed by `~/.local/lib/kion-aws-cache`. Commands:
  - `source ~/.local/bin/kac ensure` — **(preferred)** load valid creds into
    the current shell, refreshing automatically via `gkion` if the cache is
    empty or expired. `gkion` writes the fresh creds back to
    `~/.cache/kion-aws-cache/` as a side-effect.
  - `source ~/.local/bin/kac dump` — write current valid AWS env vars to
    `~/.cache/kion-aws-cache/`
  - `source ~/.local/bin/kac load` — restore vars from cache into current
    shell. Validates but does **not** refresh: expired creds fail instead of
    self-healing — agents/scripts use `ensure` instead
  - `source ~/.local/bin/kac clear` — unset vars and remove cache files
  - `source ~/.local/bin/kac status` — print whether current/cached creds are
    valid
- **`monitor-gh-run <run-id>`** — Poll a GitHub Actions run, printing per-job
  status transitions. Cancels older duplicate runs; switches to newer runs
  automatically. Exits 0 on success, 1 on failure. Deps: `gh`, `jq`.
- **`gh-graphql <task-tag> <query-file> [--jq <jq-file>] [-F k=v ...]`** —
  File-backed `gh api graphql` runner. Snapshots the query (and optional jq
  filter) to `~/.cache/<agent>/<task-tag>-<timestamp>.{graphql,jq}`, then calls
  `gh api graphql -F query=@<file>` with the snapshotted filter, passing through
  any extra `-F`/`-f`/`--paginate` args. Enforces the only sanctioned shape for
  GraphQL + jq pipelines — no inline brace/quote rot. See the
  gh-graphql-jq-pipelines skill. Deps: `gh`.
- **`jira-my-tickets`** — Print open Jira tickets assigned to the current user
  (status not Done, ordered by rank). Reads token from
  `~/.config/ops-agent/jira-token` and email from
  `~/.config/ops-agent/jira-email` (falls back to `git config user.email`).
- **`cache-scan`** — Scan the agent log dir for recent activity. **Terse by
  default** (token-lean, since an agent reads it): a one-line-per-session
  overview plus the commands that hit stderr or were interrupted.
  `-v|--verbose` adds the command timeline and heuristic keyword scan. Flags:
  `--days N` (default 2), `--date YYYY-MM-DD`, `--session ID`, `--limit N`.
  De-duplicates the `~/.cache/claude` symlink. Prefer this over hand-rolled
  `rg` sweeps of the log dir.
- **`sync-to-gdrive`** — Sync `~/.config`, `~/.local`, and `~/.cache/copilot`
  to Google Drive
  (`~/Library/CloudStorage/GoogleDrive-jhettenh@gmail.com/My Drive/42245/dotfiles`).
  Uses the unison profile at `$UNISON/gdrive-dotfiles.prf`. Sensitive dirs
  (sops, ops-agent, gh tokens) and large regenerable caches are excluded.
  Run: `sync-to-gdrive` or `sync-to-gdrive --verbose`.
- **`toggle-browser`** — Toggle macOS default browser between Vivaldi and
  Safari (darwin only).
- **`ops-agent`** — Deployed via `home-manager/common.nix` as
  `writeShellScriptBin` (source `ai-tools/scripts/ops-agent.py`).

## Automation Scripts (~/.local/bin/ai-tools)

Hook/automation scripts deployed by home-manager from `ai-tools/scripts/`.
The subdirectory is deliberately **not** on `$PATH` — these are invoked by
agent hooks / MCP clients via absolute path, never by hand.

- **`log-bash.sh`** — Bash `PostToolUse` hook logger. Wired for Claude via
  `~/.config/claude/settings.json` and for Copilot via
  `~/.config/copilot/hooks/log-bash.json`. For every Bash tool call it appends
  a structured record to `~/.cache/<agent>/session_<id>.log`:

  ```text
  ## [YYYY-MM-DD HH:MM:SS] status=ok|stderr|interrupted cwd=<dir>
  CMD: <command>
  STDOUT:   (large output truncated)
  STDERR:   (only when stderr is non-empty)
  ```

  `status` is a heuristic — the hook payload carries no exit code, so it is
  `interrupted`, else `stderr` when stderr is non-empty, else `ok`. When
  reading logs directly, grep `^##` for a command timeline and
  `status=stderr|interrupted` for likely failures.
- **`log-skill.sh`** — Skill-invocation hook logger. Wired for Claude via the
  `PostToolUse` `Skill` matcher (injected by the `ensureClaudeHook`
  activation) and for Copilot via `~/.config/copilot/hooks/log-skill.json`.
  For every `Skill` tool call — model-initiated invocations as well as skill
  slash-commands — it appends a record to
  `~/.cache/<agent>/session_<id>.skills.log`:

  ```text
  ## [YYYY-MM-DD HH:MM:SS] skill=<name> cwd=<dir>
  ARGS: <args>
  RESULT:   (only when the tool response carries text; large output truncated)
  ```

  Built-in commands like `/model` or `/clear` do **not** route through the
  Skill tool and are intentionally not captured. Handles both Claude
  (`tool_input.skill`) and Copilot (`toolName`) payload shapes.
- **`log-thinking.sh`** — agent-reasoning logger. Wired as Claude
  `Stop`/`SubagentStop` hooks and a Copilot `postToolUse` hook. Appends new
  reasoning to `~/.cache/<agent>/session_<id>.thinking.log`, deduped by a
  per-source line cursor. Best-effort for Claude (some sessions persist only
  encrypted signatures). **Security**: reasoning can contain secret values;
  known secrets and token-shaped strings are redacted before write, files are
  `0600`, and `*.thinking.log` is excluded from the gdrive sync profile.
  Treat these logs as sensitive regardless.
- **`compress-old-cache`** — Compress `~/.cache/<agent>/` files older than 15
  days with zstd. Agent-aware via `AGENT_NAME` (or explicit `CACHE_DIR`) and
  self-throttling (`COMPRESS_OLD_CACHE_MIN_INTERVAL_SEC`, default 1800s).
  Invoked by agent hooks and a daily systemd/launchd timer.
- **`claude-cache-stats`** — Claude `SessionEnd` hook; appends a one-line
  prompt-cache-hit summary per session to `cache-stats.log`.
- **`aws-mcp-server`** — MCP wrapper for the AWS API MCP server.

## Shared Package Set

The shared package set in `home-manager/common.nix` usually provides these CLI
tools on managed hosts (filtered by host support — verify with `command -v`
when portability matters): git, gh, gh-dash, lazygit, delta, curl, wget, gcc,
go, gopls, govulncheck, delve (`dlv`), go-task (`task`), pkg-config, python3,
pipx, uv, maven, awscli2, awslogs, aws-sam-cli, checkov, bun, docker,
docker-buildx, docker-compose, overmind, bat, eza, fzf, fd, ripgrep (`rg`),
sd, jq, yq-go (`yq`), zoxide, direnv, dasel, gron, tmux, age, sops, zstd,
unzip, p7zip (`7z`/`7za`/`7zr`), alejandra, ncdu, statix, deadnix, nixd,
markdownlint-cli2, ruff, shellcheck, shfmt, yamllint, taplo, unison, chezmoi,
glow, gum, tealdeer, scrcpy, file, which, tree, rsync, btop, and lsof.

Known gaps and traps (verified on managed darwin hosts):

- **`psql` is NOT installed.** For a local database, exec into its container:
  `docker exec -i <db-container> psql -U <user> <db>`. Don't retry bare `psql`.
- **`nc` is BSD** (`/usr/bin/nc`) — GNU netcat flags (`-q`, `-N`) don't exist.
- **GNU coreutils (incl. `timeout`, GNU `stat`) live on the login PATH only.**
  A bare `zsh -c`, `env -i`, or `sudo` gets the system default PATH where they
  are missing or BSD-flavored — use `zsh -lc`, pass `PATH` explicitly, or use
  absolute paths (see the shell-pitfalls skill, "Subshell PATH loss").

## macOS (darwin) Quirks

- **Homebrew cask upgrades can fail on root-owned / TCC-protected apps**
  (observed: Chrome, Slack). `task switch` treats these as non-fatal, but the
  upgrade stays blocked until the terminal app (or `brew`'s parent process)
  has a **Full Disk Access** grant in System Settings → Privacy & Security,
  and any root-owned copy under `/Applications` is reset
  (`sudo chown -R "$USER" /Applications/<App>.app` or remove the stale
  Caskroom entry and reinstall). This needs the user at the keyboard — report
  it, don't loop retries. VPN-blocked cask downloads are likewise tolerated
  and retried on a later switch (see hosts/darwin).

## Instruction Deployment & Regeneration

`agent-defaults.md` is the single source of truth for the always-on prefix.
It is rendered by `home-manager/lib/agent-instructions.nix` (substituting
`@@AGENT@@` with the agent name) and deployed as read-only symlinks resolving
through the active home-manager generation:

**Claude** (loaded via `CLAUDE_CONFIG_DIR` or fallback):

- `~/.config/claude/CLAUDE.md` — primary
- `~/.claude/CLAUDE.md` — fallback / memory resolution path

**Copilot:**

- `~/.config/github-copilot/copilot-defaults.instructions.md` — Copilot CLI
- `~/Library/Application Support/Code/User/prompts/copilot-defaults.instructions.md`
  — VS Code stable (macOS)
- `~/Library/Application Support/Code - Insiders/User/prompts/copilot-defaults.instructions.md`
  — VS Code Insiders (macOS)
- `~/.config/Code/User/prompts/copilot-defaults.instructions.md` — VS Code
  (Linux/XDG)
- `~/.vscode-server/data/User/prompts/copilot-defaults.instructions.md` —
  VS Code Server

To find the active nix store path for a given agent:

```sh
readlink -f ~/.config/claude/CLAUDE.md          # Claude variant
readlink -f ~/.config/github-copilot/copilot-defaults.instructions.md  # Copilot variant
```

After editing `agent-defaults.md`, regenerate the committed copies
(`chezmoi/dot_config/claude/CLAUDE.md`, the Copilot instruction files, and
`.github/copilot-instructions.md`) and keep them in the same commit:

```sh
task generate:agent-instructions
```

`task check:agent-instructions`, `task check:copilot-instructions`, and
`task check:instruction-size` guard drift and token bloat in pre-commit and
CI.
