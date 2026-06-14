# Nix Configuration

Jeremy's personal system configuration. A **single flake** manages NixOS, NixOS-WSL, and macOS
(via Home Manager, NixOS-WSL, and nix-darwin), while **chezmoi** layers dotfiles on top — including
on Windows-native hosts that have no Nix at all. Both halves live in this one repository.

Everything is driven through [`task`](https://taskfile.dev) so you never hand-assemble
`nixos-rebuild` / `darwin-rebuild` / `home-manager` invocations. The taskfile detects your platform
and routes to the right configuration automatically.

## Highlights

- **One flake, three platforms** — `darwin`, `linux`, and `wsl` hosts share a common Home Manager base.
- **Nix + chezmoi hybrid** — Nix owns packages and system state; chezmoi owns dotfiles and reaches the
  one place Nix can't (native Windows).
- **Single-source color palette** — Monokai Spectrum is defined once and consumed by Nix, Stylix, and
  chezmoi alike (see [Color palette](#color-palette)).
- **AI tooling as code** — Claude Code / Copilot skills, agents, and instructions are version-controlled
  and deployed declaratively (see [AI tooling](#ai-tooling-skills--agents)).

## Quick start

### Linux / WSL

`install.sh` bootstraps a fresh WSL2 or bare Ubuntu/Debian box: it installs Nix (Determinate Systems
installer), runs chezmoi and Home Manager, sets zsh as the default shell, bootstraps Windows-side tools
(WSL only), and provisions secrets interactively. You don't need it on macOS or an existing NixOS system —
use the [task commands](#everyday-commands) directly there.

NixOS-WSL ships Nix but **no native `git`** until this config is applied, and has flakes disabled by
default. Clone with an ephemeral Nix-provided git so the experimental features are enabled inline.
**Do not use Windows `git.exe`** — it rewrites the scripts with CRLF endings and you'll hit
`env: 'bash\r': No such file or directory`:

```bash
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git \
  --command git clone https://github.com/borland502/nix-config ~/.config/nix
cd ~/.config/nix
./install.sh
```

On a fresh Debian/Ubuntu WSL with no Nix yet, install the distro git first
(`sudo apt-get install -y git`). The repo's `.gitattributes` forces LF, so even an accidental
`git.exe` clone stays runnable.

### macOS

Use Homebrew + nix-darwin, then:

```bash
task switch          # auto-detects darwin
```

### Windows (native, no WSL)

```powershell
task windows-bootstrap          # installs Scoop, a curated package set, Nerd Font, Windows Terminal config
task chezmoi-init
task chezmoi-apply              # deploys PowerShell profile, flameshot config, color scheme, agent instructions
```

Windows support is deliberately minimal — mostly helper scripts, usually run after an initial WSL pass.

## Everyday commands

```bash
task build            # build only, no activation
task switch           # build + activate (auto-detects host)
task home-switch      # Home Manager only, no system rebuild
task check            # validate the flake
task fmt              # format Nix files (alejandra)
task lint             # run all linters

task upgrade          # update flake inputs + switch
task update           # update flake inputs only
task gc               # garbage-collect old generations
task optimize         # deduplicate the Nix store
```

`switch` (and friends) automatically run chezmoi apply, formatting, and agent-instruction regeneration
before rebuilding. Override platform detection on any task with `HOST=<target>`, e.g.
`task switch HOST=linux`. Shortcuts `task linux` / `task darwin` / `task wsl` are aliases for the same.

### Platform auto-detection

| Condition | Detected host |
|---|---|
| macOS (`uname` = Darwin) | `darwin` |
| Linux, hostname `nixos` or `wsl` | `wsl` |
| Linux, hostname `linux` | `linux` |
| WSL Debian / Ubuntu (`/proc/version` + `/etc/os-release`) | `debian-wsl` / `ubuntu-wsl` |
| Fallback | `linux` |

### Dev shells

```bash
nix develop          # repo editing tools: alejandra, nixd, statix, deadnix, task
nix develop .#go-gui # Go + GLFW/Fyne/CGO X11/Wayland/OpenGL headers for GUI projects
```

## Repository layout

```text
flake.nix / flake.lock      Inputs (nixpkgs, home-manager, nix-darwin, NixOS-WSL, sops-nix, stylix, …)
AGENTS.md / CLAUDE.md       Repo guide for coding agents (CLAUDE.md is a one-line @AGENTS.md pointer)
install.sh                  Fresh Linux / WSL bootstrap
taskfile.yaml               All build, switch, and maintenance tasks
hosts/                      System-level definitions: darwin/, linux/, wsl/
modules/                    Shared system modules (e.g. audio/pulseaudio.nix)
home-manager/               Shared user config — common.nix (packages), per-platform entrypoints,
                              zsh.nix, starship.nix, lib/ (renderers & helpers), profiles/
chezmoi/                    chezmoi-managed dotfiles for every platform (incl. Windows)
ai-tools/                   Skills, agents, and the Claude Code plugin marketplace
scripts/                    Provisioning and CI helper scripts
docs/                       Design notes (e.g. agent-token-cost-levers.md)
.github/workflows/          CI: nix-validation, secrets-scan, update-flake
```

## Available hosts

- **darwin** — macOS via nix-darwin + Home Manager. (`ICFGG241C3Y03` is a legacy alias for the same config.)
- **linux** — NixOS with KDE Plasma, development tooling, and desktop packages.
- **wsl** — NixOS-WSL. `hosts/wsl/default.nix` sets the hostname to `wsl` so auto-detection works after
  the first switch.

> **First WSL switch:** before your new local files are tracked by Git, use a path-based flake reference:
>
> ```bash
> NIX_CONFIG="experimental-features = nix-command flakes" sudo nixos-rebuild switch --flake "path:$PWD#wsl"
> ```
>
> After that, the `task wsl` / `task home-switch` aliases work normally.

## Home Manager profiles

Shared dev tools (`git`, `gh`, `go`, `ripgrep`, `fzf`, `jq`, `docker`, `awscli2`, and many more) live in
`common.nix` and apply everywhere. Linux layers two profiles on top:

- **Development** (`profiles/development-linux.nix`) — Neovim, VS Code (non-WSL) with a curated extension
  set, gnumake/cmake, Node.js, kubectl.
- **Desktop** (`profiles/desktop-linux.nix`) — Firefox + Vivaldi (default), VLC/mpv, Discord/Slack,
  LibreOffice/Obsidian/KeePassXC, GIMP/Inkscape/Flameshot.

## Chezmoi dotfile management

Chezmoi's source directory is `chezmoi/` in this repo. `task chezmoi-init` writes
`~/.config/chezmoi/chezmoi.toml` to point there; on Linux and macOS, Home Manager activation does the
same automatically on every `task switch`.

```bash
task chezmoi-apply              # apply dotfiles to your home directory
task chezmoi-add FILE=~/.somerc # bring a file under management
task chezmoi-diff               # preview pending changes
```

`.chezmoiignore` is a Go template that splits behavior by platform:

- **Linux / macOS** — agent instruction files are ignored (Home Manager owns them via Nix store
  symlinks), as are Windows-only files.
- **Windows** — everything is deployed, since Home Manager isn't available: agent instructions,
  PowerShell profiles, `~/.local/bin` scripts, flameshot config, and more.

On Windows, `run_onchange_deploy-vscode-instructions.ps1.tmpl` additionally copies the Copilot
instructions into `%APPDATA%\Code\User\prompts\`, where native VS Code reads them. (It's a no-op
elsewhere.)

## Color palette

The Monokai Spectrum palette is defined **once** in `chezmoi/dot_config/colors/monokai.toml` and reused
everywhere:

- Parsed at Nix eval time (`builtins.fromTOML` in `home-manager/lib/colors.nix`)
- Fed to Stylix as the `base16Scheme`, which themes bat, btop, fzf, kitty, Starship, Vim, VS Code, GTK,
  and KDE automatically
- Referenced by `starship-settings.nix`, `zsh.nix`, and the per-platform Home Manager entrypoints
- Deployed to `~/.config/colors/monokai.toml` by chezmoi on all platforms, and read by the PowerShell
  profile's `$Monokai` table for PSReadLine and fzf theming

## AI tooling (skills + agents)

Custom skills, agents, and instructions live in [`ai-tools/`](ai-tools/) as the single source of truth,
modeled on the [obra/superpowers](https://github.com/obra/superpowers) layout:

```text
ai-tools/
├── .claude-plugin/   Marketplace + plugin metadata registering nix-config-tools
├── agents/           Custom sub-agents (*.agent.md)
├── skills/           Always-on core set (flow, git, ops, sec, web, shell)
└── skills-stack/     Stack-specific set (Angular, Spring Boot, Go, Python, JS/TS, …) — opt-in per project
```

### Core vs. stack skills

Every globally deployed skill injects its description into **every** session's system prompt, so only the
core set in `skills/` ships globally. Language/framework skills live in `skills-stack/` and are linked
into just the projects that use them:

```bash
task skills:enable SKILL=springboot-patterns DIR=~/src/my-service
```

That symlinks the skill into `<project>/.claude/skills/`, where it loads only for sessions in that
project. Generated `*.prompt.md` bridges keep stack skills reachable on-demand in VS Code Copilot Chat
via `/`. Skills and agents are deployed as on-demand slash commands, **not** always-on instructions —
only `copilot-defaults.instructions.md` carries `applyTo: "**"`, keeping the always-on surface to one file.

The `registerClaudeMarketplaces` activation hook idempotently registers two marketplaces in
`~/.config/claude/settings.json`: `nix-config-dev` (this repo's `ai-tools`, enabling `nix-config-tools`)
and `anthropic-agent-skills` (a chezmoi external at `~/.local/src/ai-tools/anthropic-skills`, enabling
`document-skills` and `claude-api`). The proprietary `document-skills` plugin is loaded directly from
the upstream checkout and never copied into this repo.

### Agent instructions

Instructions use a **tiny-root** split (from
[khaneliman/khanelinix](https://github.com/khaneliman/khanelinix)): a small always-on prefix, with detail
in an on-demand reference that costs zero prompt tokens until an agent opens it.

```text
chezmoi/dot_config/instructions/agent-defaults.md   Behavioral rules — rendered into every session prompt
chezmoi/dot_config/instructions/agent-reference.md  Credential catalog, script usage, deploy paths — on demand
```

`agent-defaults.md` is budgeted (120 lines / 7 KB, enforced by `task check:instruction-size`); reference
material belongs in `agent-reference.md`. The `@@AGENT@@` placeholder is substituted per agent at render
time. On Linux/macOS/WSL, `home-manager/lib/agent-instructions.nix` renders the files; on Windows,
chezmoi deploys pre-rendered copies committed to the repo.

**When you edit `agent-defaults.md`, regenerate and commit the rendered copies together:**

```bash
task generate:agent-instructions
```

The pre-commit hook and CI catch drift via `task check:agent-instructions`.

> **Claude Code in VS Code:** the shared settings set `claudeCode.useTerminal = true` so the CLI runs in
> the integrated terminal. This is **required** — the terminal session loads the managed zsh environment
> (nix-provided `rg`/`fd`/`jq`, aliases, PATH) and fires the logging hooks below. If you toggle it off in
> the Settings UI, the next `home-switch` restores it.

### Activity logs & `cache-scan`

Agent sessions are logged to `~/.cache/<agent>/` (with `~/.cache/claude` symlinked to `~/.cache/copilot`
so both share one dir) by hooks deployed from `ai-tools/scripts/` to `~/.local/bin/ai-tools/` (an
intentionally off-`PATH` location — these are hook/MCP scripts, not for manual use):

| Script | Hook | Captures |
|---|---|---|
| `log-bash.sh` | Bash `PostToolUse` | each command + stdout/stderr → `session_<id>.log` |
| `log-thinking.sh` | `Stop` / `SubagentStop` (Claude), `postToolUse` (Copilot) | agent reasoning → `session_<id>.thinking.log` |
| `claude-cache-stats` | `SessionEnd` | prompt-cache-hit summary → `cache-stats.log` |

Read it back with **`cache-scan`** — terse by default, `--verbose` adds the full command timeline and a
keyword scan (`--days N`, `--date`, `--session ID`, `--limit N`).

> **Security:** `*.thinking.log` can contain secret *values* an agent reasoned about. Known secrets are
> redacted, files are written `0600`, and these logs are excluded from the gdrive sync profile. Treat the
> cache logs as sensitive. Token-cost levers are documented in
> [docs/agent-token-cost-levers.md](docs/agent-token-cost-levers.md).

## PowerShell profile

The chezmoi-managed PowerShell profile (`chezmoi/dot_Documents/PowerShell/`) mirrors the zsh setup:
PSReadLine in Vi mode with Monokai colors and fzf-powered Ctrl+R, tool aliases (bat/eza/ripgrep/zoxide),
fzf theming, Starship (sharing `~/.config/starship.toml` with WSL), and XDG environment variables.

It uses chezmoi's `create_` prefix, so it's written only if no profile exists yet — your customizations
are preserved. PowerShell 5.1 gets a thin redirector that dot-sources the PS7 profile. On WSL, Home
Manager deploys `starship.toml` to the Windows home and bootstraps Starship + PowerShell 7 via winget;
chezmoi owns the profile, Home Manager owns the Starship config.

## Editor configuration

- `home-manager/lib/code-editor-user-settings.nix` is the shared source for VS Code user settings;
  `common.nix` and `home-darwin.nix` install them and the Copilot prompt files into each editor.
- `.devcontainer/devcontainer.json` bootstraps container sessions before the Home Manager profile applies.
- `.vscode/` is repo-workspace-specific (Nix formatter, language server, extension recommendations) and
  should stay focused on this repository.
- Rule of thumb: settings that should follow you across machines belong in Home Manager; settings that
  apply only to this repo belong in `.vscode/`.

## Modules

- **Audio (`modules/audio/pulseaudio.nix`)** — disables legacy PulseAudio and enables PipeWire with ALSA,
  PulseAudio compatibility, and Real-Time Kit support.

Inspect user services through tasks:

```bash
task service-status SERVICE=pipewire.service   # systemctl --user
task logs SERVICE=pipewire.service             # journalctl --user
```

## Platform notes

- **macOS** — nix-darwin for system settings, Home Manager for user config; Firefox via Homebrew casks
  (the Stylix Firefox target is disabled here).
- **WSL** — NixOS-WSL base; `programs.nix-ld` is enabled so VS Code Remote / `.vscode-server` binaries
  run on NixOS. `install.sh` detects WSL, enables interop in `/etc/wsl.conf`, and runs the Windows
  bootstrap; `task wsl-bootstrap-windows` sets up Scoop, the Nerd Font, and Windows Terminal.
- **Windows (native)** — `task windows-bootstrap` is the entry point; chezmoi manages everything since
  Home Manager is unavailable. Flameshot uses Alt+Shift+3/4 (vs. Ctrl+Shift+3/4 on Linux/macOS).

## Customization

1. Update user info in the relevant host or Home Manager profile.
2. Add/remove packages in `home-manager/common.nix` (shared) or a platform profile.
3. Edit `chezmoi/dot_config/instructions/agent-defaults.md` for agent changes, then run
   `task generate:agent-instructions` and commit the result.
4. Edit `chezmoi/dot_config/colors/monokai.toml` to change the palette — Nix, Stylix, and chezmoi all
   read it.

## Maintenance & CI

```bash
task update && task switch        # keep the system current (CI also opens a weekly update PR)
task gc / task optimize           # clean up generations / dedupe the store
task generate:agent-instructions  # re-render agent files after editing the source
task check:instruction-size       # guard the always-on prefix against bloat
```

Run `task hooks:install` once per clone to use the tracked hooks in `.githooks/`. The pre-commit hook
runs `task lint:nix` (statix, deadnix, and the `check:agent-instructions` / `check:copilot-instructions`
drift checks).

CI validates Linux and macOS by building flake outputs and the WSL target by building
`nixosConfigurations.wsl` (GitHub runners have no real WSL2, so end-to-end boot tests need a self-hosted
Windows runner). `update-flake.yml` bumps `flake.lock` weekly (Mondays 05:17 UTC, or on demand) and
opens a labeled PR. Note: PRs opened with the default `GITHUB_TOKEN` don't trigger validation
automatically — close/reopen or push to the branch to run CI before merging.

## Credits

This project's own code is MIT-licensed ([LICENSE](LICENSE)). Ingested upstream skills under
`ai-tools/skills/` and `ai-tools/skills-stack/` retain their original licenses and `origin:` frontmatter;
project-local skills (`ops-*`, `flow-reconciliation`, `sec-credentials`, `sec-sops-encrypt`,
`shell-pitfalls`) are original to this repo.

| Upstream | License | Borrowed |
|---|---|---|
| [anthropics/skills](https://github.com/anthropics/skills) | Apache 2.0 / proprietary | `claude-api`, `document-skills` (loaded via marketplace, not redistributed) |
| [obra/superpowers](https://github.com/obra/superpowers) | MIT | `flow-*`, `git-worktrees`, `git-finish-branch`, `git-request-review` |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | `golang-*`, `python-*`, `springboot-*`, `github-ops`, `ops-jira-integration`, `ops-repo-scan`, `git-workflow`, `security-*` |
| [appautomaton/webmaton](https://github.com/appautomaton/webmaton) | MIT | `web-*` |
| [angular/skills](https://github.com/angular/skills) | MIT (Google LLC) | `angular-developer`, `angular-new-app` |

Organizational patterns (reimplemented, not copied) come from
[khaneliman/khanelinix](https://github.com/khaneliman/khanelinix) (tiny-root agent instructions, core
vs. opt-in skill split), [wimpysworld/nix-config](https://github.com/wimpysworld/nix-config) (task-runner
as the documented agent interface), [budimanjojo/nix-config](https://github.com/budimanjojo/nix-config)
(scheduled dependency-update PRs), and
[dhupee/dotfiles](https://github.com/dhupee/dotfiles) /
[dc-tec/nixos-config](https://github.com/dc-tec/nixos-config) (chezmoi + single-flake multi-platform prior
art).

When upstream externals refresh (every ~720h), reconcile local divergence with the
[`flow-reconciliation` skill](ai-tools/skills/flow-reconciliation/SKILL.md) so local edits aren't silently
overwritten.
