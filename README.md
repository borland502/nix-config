# Nix Configuration

Jeremy's personal Nix configuration with modular organization for NixOS, WSL, and macOS via Home Manager, NixOS-WSL,
and nix-darwin. Dotfiles for all platforms (including Windows-native) are managed through chezmoi, backed by this same
repository.

## Structure

```text
├── flake.nix                               # Flake inputs and platform outputs
├── flake.lock                              # Locked flake input revisions
├── install.sh                              # Bootstrap script for fresh Linux / WSL installs
├── taskfile.yaml                           # Common build, switch, and maintenance tasks
├── scripts/
│   ├── check-copilot-instructions-sync.sh  # CI check: .github/copilot-instructions.md in sync
│   ├── provision-secrets.sh                # Interactive secret provisioning (age key)
│   └── wsl/
│       ├── bootstrap-windows.sh            # WSL entrypoint for Windows bootstrap
│       └── bootstrap-windows.ps1           # Windows-side Scoop/font/package bootstrap
├── chezmoi/                                # Chezmoi-managed dotfiles (all platforms)
│   ├── .chezmoiignore                      # Platform-conditional ignore rules
│   ├── dot_claude/CLAUDE.md                # Claude Code agent instructions
│   ├── dot_config/
│   │   ├── colors/monokai.toml             # Monokai Spectrum palette (single source of truth)
│   │   ├── flameshot/flameshot.ini.tmpl    # Flameshot config (OS-conditional shortcuts)
│   │   ├── instructions/agent-defaults.md  # Single source for all agent instructions
│   │   ├── kitty/kitty.conf                # Kitty terminal base configuration
│   │   ├── github-copilot/                 # Copilot instructions (VS Code, IntelliJ)
│   │   └── Code/User/prompts/              # VS Code Copilot prompt files
│   ├── dot_Documents/
│   │   ├── PowerShell/                     # PowerShell 7 profile (Windows, create-only)
│   │   └── WindowsPowerShell/              # PowerShell 5.1 redirector (Windows, create-only)
│   ├── dot_local/bin/                      # Manual user scripts → ~/.local/bin (ai-tools/ = hook/MCP scripts, not on PATH)
│   └── run_onchange_deploy-vscode-instructions.ps1.tmpl  # Windows APPDATA sync
├── hosts/                                  # System-level host definitions
│   ├── darwin/default.nix                  # nix-darwin system configuration
│   ├── linux/default.nix                   # NixOS module for the linux target
│   ├── linux/hardware-configuration.nix
│   └── wsl/default.nix                     # NixOS-WSL host configuration
├── modules/
│   └── audio/pulseaudio.nix               # Shared audio/PipeWire module
├── home-manager/
│   ├── common.nix                          # Shared Home Manager base config
│   ├── home.nix                            # Linux Home Manager entrypoint
│   ├── home-darwin.nix                     # macOS Home Manager entrypoint
│   ├── home-wsl.nix                        # WSL Home Manager entrypoint
│   ├── zsh.nix                             # Shared shell configuration
│   ├── starship.nix                        # Shared prompt configuration
│   ├── lib/
│   │   ├── agent-instructions.nix          # Renders agent-defaults.md per agent
│   │   ├── code-editor-user-settings.nix   # Shared VS Code user settings
│   │   ├── colors.nix                      # Reads chezmoi/dot_config/colors/monokai.toml
│   │   └── starship-settings.nix           # Starship prompt settings (uses colors.nix)
│   └── profiles/
│       ├── development-linux.nix           # Linux development packages
│       └── desktop-linux.nix              # Linux desktop packages
├── .devcontainer/devcontainer.json         # Devcontainer bootstrap for Home Manager outputs
├── .github/
│   ├── copilot-instructions.md             # Mirror of agent-defaults.md for GitHub Copilot
│   └── workflows/nix-validation.yml
└── .vscode/                                # Repo-local VS Code recommendations/settings
```

## Quick Start

> **Linux / WSL users:** The `install.sh` script at the repo root is designed for fresh WSL2 or bare Ubuntu/Debian
> installs where Nix is used in place of Linuxbrew. It bootstraps Nix via the Determinate Systems installer, runs
> chezmoi and Home Manager, sets zsh as the default shell, bootstraps Windows-side tools (WSL only), and runs
> interactive secret provisioning. It is not needed on macOS (use Homebrew + nix-darwin) or on an existing NixOS
> system (use the task commands below directly).

### Platform Auto-Detection

The taskfile detects the host platform at runtime and routes to the correct configuration automatically:

| Condition | Detected host |
|---|---|
| macOS (`uname` = Darwin) | `darwin` |
| Linux with hostname `nixos` or `wsl` | `wsl` |
| Linux with hostname `linux` | `linux` |
| WSL Debian (via `/proc/version` + `/etc/os-release`) | `debian-wsl` |
| WSL Ubuntu (via `/proc/version` + `/etc/os-release`) | `ubuntu-wsl` |
| Fallback | `linux` |

Override detection with `HOST=<target>` on any task: `task switch HOST=linux`.

### Building and Switching

```bash
# Auto-detect platform and build/switch
task build
task switch

# Explicit platform targets
task switch HOST=linux
task switch HOST=darwin
task switch HOST=wsl

# Platform-specific shortcuts
task linux          # equivalent to task switch HOST=linux
task darwin         # equivalent to task switch HOST=darwin
task wsl            # equivalent to task switch HOST=wsl

# Home Manager only (without NixOS system rebuild)
task home-switch

# Update flake inputs and rebuild
task upgrade

# Update flake inputs only
task update

# Garbage collect old generations
task gc

# Optimize the Nix store
task optimize

# Format nix files
task fmt

# Check flake for errors
task check
```

The `switch`, `upgrade`, `home-switch`, `darwin-switch`, and `nixos-switch` tasks automatically ensure chezmoi is
initialized and applied before rebuilding the system.

### Initial Chezmoi Setup

After cloning the repo, run once to point chezmoi at this repo as its source directory:

```bash
task chezmoi-init
```

Then apply dotfiles to your home directory:

```bash
task chezmoi-apply
```

To add a new file to chezmoi management:

```bash
task chezmoi-add FILE=~/.somerc
```

On Linux and macOS, home-manager manages the agent instruction files and chezmoi ignores them (via `.chezmoiignore`).
On Windows, chezmoi deploys them directly.

### Windows Bootstrap

To set up a Windows machine without WSL, run natively in PowerShell from the repo root:

```powershell
task windows-bootstrap
```

This installs Scoop, creates standard XDG directories (`~/.local/bin`, `~/.config`, `~/.cache`, etc.), installs a
curated package set (git, chezmoi, task, ripgrep, fzf, fd, bat, flameshot, go, jq, neovim, and others), adds
`~/.local/bin` to the user Path, installs the FiraCode Nerd Font, and configures Windows Terminal to use it.

After bootstrap, run `task chezmoi-init` and `task chezmoi-apply` to deploy dotfiles — including the PowerShell
profile, flameshot config, and color scheme.

> Note: Windows support is nothing fancy, mostly a bunch of helper scripts after an initial run by WSL

### WSL Bootstrap

On a fresh NixOS-WSL instance, use a path-based flake reference for the first switch so newly added local files are
included before they are tracked by Git:

```bash
cd ~/nix-config
NIX_CONFIG="experimental-features = nix-command flakes" sudo nixos-rebuild switch --flake "path:$PWD#wsl"
```

After the initial switch, use the task aliases:

```bash
task wsl
task home-switch
task wsl-bootstrap-windows   # bootstrap Windows-side tools from WSL
```

### macOS Setup

```bash
task build
task switch
task darwin-build
task darwin-switch
```

### Repository Dev Shell

For repo-local editing tools (`alejandra`, `nixd`, `statix`, `deadnix`, `task`):

```bash
nix develop
```

### Go GUI Dev Shell

For Go projects that need GLFW, Fyne, or other CGO-backed X11/OpenGL dependencies:

```bash
nix develop .#go-gui
```

Provides Go, gopls, govulncheck, delve, pkg-config, and the required X11, Wayland, and OpenGL development headers and libraries.

## Available Hosts

- **darwin**: macOS configuration using nix-darwin and Home Manager. The alias `ICFGG241C3Y03` points to the same
  Darwin configuration for backwards compatibility.
- **linux**: NixOS with KDE Plasma, development tooling, and desktop packages.
- **wsl**: NixOS-WSL. Hostname is set to `wsl` by `hosts/wsl/default.nix` so platform auto-detection works after first switch.

## Chezmoi Dotfile Management

Chezmoi source directory is `chezmoi/` in this repo. The `chezmoi-init` task writes `~/.config/chezmoi/chezmoi.toml`
pointing there; home-manager activation does the same automatically on Linux and macOS after any `task switch`.

`.chezmoiignore` is a Go template that conditionally ignores files based on platform:

- **Linux / macOS**: agent instruction paths are ignored — home-manager owns them via Nix store symlinks. Windows-only
  files (`Documents/PowerShell`, `.local/bin/update_scoop.ps1`) are also ignored.
- **Windows**: all chezmoi-managed files are deployed, including `~/.claude/CLAUDE.md`, Copilot instruction files,
  PowerShell profiles, `~/.local/bin` scripts, and flameshot config.

The `run_onchange_deploy-vscode-instructions.ps1.tmpl` script (Windows-only, skipped elsewhere via empty template
body) additionally copies the Copilot instructions from the chezmoi-managed XDG path to `%APPDATA%\Code\User\prompts\`,
which is where Windows-native VS Code reads them.

## Color Palette

The Monokai Spectrum color palette is defined once in `chezmoi/dot_config/colors/monokai.toml`. This single TOML file is:

- Parsed at Nix eval time via `builtins.fromTOML` in `home-manager/lib/colors.nix`
- Fed to Stylix as the `base16Scheme` in `common.nix`
- Used by `starship-settings.nix`, `zsh.nix`, `home-wsl.nix`, and `home-darwin.nix` for color references
- Deployed to `~/.config/colors/monokai.toml` by chezmoi on all platforms
- Referenced by the PowerShell profile's `$Monokai` hashtable for PSReadLine and fzf theming

Stylix applies the palette automatically to bat, btop, fzf, kitty, Starship, Vim, VS Code, GTK, and KDE.

## Agent Instructions

All agent instructions derive from a single source file:

```text
chezmoi/dot_config/instructions/agent-defaults.md
```

The `@@AGENT@@` placeholder is substituted per agent at render time.

| Platform | Renderer | Deployed paths |
|---|---|---|
| Linux / macOS / WSL | `home-manager/lib/agent-instructions.nix` via `pkgs.writeText` | `~/.claude/CLAUDE.md`, `~/.config/github-copilot/…`, `~/.config/Code/User/prompts/…`, `~/.vscode-server/…` |
| Windows | chezmoi (pre-rendered files committed to `chezmoi/`) | same XDG paths + `%APPDATA%\Code\User\prompts\…` via run script |

When you edit `agent-defaults.md`, regenerate the chezmoi files and commit them together:

```bash
task generate:agent-instructions
```

The pre-commit hook and CI catch drift automatically via `task check:agent-instructions`.

### Agent activity logs & `cache-scan`

Agent sessions are logged to `~/.cache/<agent>/` (with `~/.cache/claude` symlinked
to `~/.cache/copilot` so both share one dir) by hooks deployed from
`chezmoi/dot_local/bin/ai-tools/` (automation scripts not meant for manual use;
deployed to `~/.local/bin/ai-tools/`, which is intentionally not on `$PATH`):

| Script | Hook | Captures → file |
|---|---|---|
| `log-bash.sh` | Bash `PostToolUse` | each command + stdout/stderr → `session_<id>.log` (`## [ts] status=ok\|stderr\|interrupted cwd=…`) |
| `log-thinking.sh` | Claude `Stop`/`SubagentStop`, Copilot `postToolUse` | agent reasoning → `session_<id>.thinking.log` (best-effort for Claude) |
| `claude-cache-stats` | Claude `SessionEnd` | one-line prompt-cache-hit summary → `cache-stats.log` |

Read it back with **`cache-scan`** — terse by default (one line per session plus
the commands that hit stderr/were interrupted), `--verbose` adds the command
timeline and a keyword scan. Flags: `--days N` (default 2), `--date`,
`--session ID`, `--limit N`, `-v|--verbose`. Output is kept token-lean because an
agent consumes it. The scripts assume GNU coreutils (`stat -c`), guaranteed by
`coreutils` in the darwin system profile (native on Linux/WSL).

**Security:** `*.thinking.log` can contain secret *values* the agent reasoned
about; reasoning logs redact known secrets, are written `0600`, and are excluded
from the gdrive sync profile. Treat the cache logs as sensitive.

## AI Tooling (Skills + Agents)

Custom skills and agents live in [`ai-tools/`](ai-tools/) as the single source of truth, modeled on the
[obra/superpowers](https://github.com/obra/superpowers) layout:

```text
ai-tools/
├── .claude-plugin/
│   ├── marketplace.json     # registers nix-config-tools as a Claude Code plugin
│   └── plugin.json          # plugin metadata
├── agents/                  # *.agent.md — four custom sub-agents
└── skills/                  # <name>/SKILL.md (+ optional references/, scripts/)
```

[`home-manager/lib/agent-instructions.nix`](home-manager/lib/agent-instructions.nix) generates bridge files and
[`home-manager/common.nix`](home-manager/common.nix) deploys them:

| Destination | File type | Frontmatter | Behaviour |
|---|---|---|---|
| `~/.config/claude/{skills,agents}` | raw `SKILL.md` / `*.agent.md` | as-authored | loaded by Claude Code marketplace |
| `~/.config/copilot/{skills,agents}` | raw `SKILL.md` / `*.agent.md` | as-authored | loaded by Copilot CLI |
| `prompts/skills/*.prompt.md` | generated bridge | `mode: ask` | invoke on-demand in VS Code Copilot Chat with `/` |
| `prompts/agents/*.prompt.md` | generated bridge | `mode: agent` | invoke on-demand in VS Code Copilot Chat with `/` |

Skills and agents are **not** deployed as always-on instruction files — only `copilot-defaults.instructions.md`
carries `applyTo: "**"`. This keeps the active instruction count to one and makes each skill or agent available
as an explicit slash command (e.g. `/flow-test-driven-development`, `/github-actions-expert`).

The `registerClaudeMarketplaces` activation hook idempotently writes the marketplace registration into
`~/.config/claude/settings.json`. Two marketplaces are registered:

| Marketplace | Source | Plugins enabled |
|---|---|---|
| `nix-config-dev` | `<repo>/ai-tools` (local) | `nix-config-tools` |
| `anthropic-agent-skills` | `~/.local/src/ai-tools/anthropic-skills` (chezmoi external) | `document-skills`, `claude-api` |

The Anthropic `document-skills` plugin (`docx`, `pdf`, `pptx`, `xlsx`) is loaded directly from the upstream checkout —
its proprietary license forbids redistribution, so this repo never copies its contents.

The shells export `CLAUDE_CONFIG_DIR` and `COPILOT_HOME` (defined in [`home-manager/zsh.nix`](home-manager/zsh.nix))
pointing at the XDG locations.

### Upstream credits

Skills under `ai-tools/skills/` other than the project-local ones (`ops-cache-scan`, `ops-chezmoi`, `cli-dasel`,
`cli-fd`, `cli-fzf`, `cli-jq`, `ops-nix-pitfalls`, `ops-agent`, `flow-reconciliation`, `cli-rg`, `cli-sd`,
`sec-credentials`, `sec-sops-encrypt`, `shell-pitfalls`, `cli-yq`) were ingested from upstream repositories. Each
retains its `origin:` frontmatter for traceability, and any required attribution / license text is preserved verbatim
alongside the skill.

| Upstream repo | License | Skills ingested |
|---|---|---|
| [anthropics/skills](https://github.com/anthropics/skills) | Apache 2.0 (`claude-api`); proprietary (`document-skills`) | Loaded via the upstream marketplace registration above. NOT redistributed. |
| [obra/superpowers](https://github.com/obra/superpowers) | MIT | `flow-writing-plans`, `flow-writing-skills`, `git-worktrees`, `flow-subagent-driven-development`, `flow-executing-plans`, `flow-test-driven-development`, `flow-systematic-debugging`, `git-finish-branch`, `git-request-review`, `flow-verification-before-completion` |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | `bun-runtime`, `golang-patterns`, `golang-testing`, `github-ops`, `ops-jira-integration`, `ops-repo-scan`, `python-patterns`, `python-testing`, `springboot-patterns`, `springboot-security`, `springboot-tdd`, `springboot-verification`, `git-workflow`, `security-review`, `security-scan` |
| [appautomaton/webmaton](https://github.com/appautomaton/webmaton) | MIT | `web-chrome-devtools-cli`, `web-html-to-markdown`, `web-nodriver-browser`, `web-playwright-cli` |
| [angular/skills](https://github.com/angular/skills) | MIT (Google LLC) | `angular-developer`, `angular-new-app` |

### Reconciling against upstream

The chezmoi externals at `~/.local/src/ai-tools/<repo>` refresh every 720h (~1 month). When upstream updates land,
follow the [`flow-reconciliation` skill](ai-tools/skills/flow-reconciliation/SKILL.md) — it documents the
diff/classify/apply procedure (and the namespace + path rewrites required after each `cp -R`), so local divergence
(e.g. the project-specific "Project Layout References" section appended to `golang-patterns` and `golang-testing`)
isn't silently overwritten.

This project's own MIT-licensed code is governed by [LICENSE](LICENSE); ingested upstream content retains its original license.

## PowerShell Profile

The chezmoi-managed PowerShell profile (`chezmoi/dot_Documents/PowerShell/`) mirrors the zsh configuration:

- **PSReadLine** in Vi mode with Monokai syntax colors, history prediction, and fzf-powered Ctrl+R
- **Tool aliases** for bat, eza, ripgrep, and zoxide
- **fzf** with Monokai color scheme
- **Starship** prompt initialization (shares `~/.config/starship.toml` with WSL)
- **XDG directory** environment variables

The profile uses chezmoi's `create_` prefix — it is only written if no profile exists yet, so user customizations are
preserved. PowerShell 5.1 gets a thin redirector that dot-sources the PS7 profile.

On WSL, home-manager deploys `starship.toml` to the Windows home directory and bootstraps starship + PowerShell 7 via
winget. Chezmoi owns the PowerShell profile; home-manager owns the starship config.

## Home Manager Profiles

### Development Profile (`profiles/development-linux.nix`)

- Editors: Neovim, VS Code (non-WSL only) with Python, GitLens, Material Icon Theme, Tailwind CSS, Prettier, and Live
  Server extensions
- Build tools: gnumake, cmake
- Runtimes: Node.js
- Cloud: kubectl

### Desktop Profile (`profiles/desktop-linux.nix`)

- Browsers: Firefox, Vivaldi (default)
- Media: VLC, mpv
- Communication: Discord, Slack
- Productivity: LibreOffice, Obsidian, KeePassXC
- Graphics: GIMP, Inkscape, Flameshot

Common development tools (`git`, `gh`, `go`, `ripgrep`, `fzf`, `jq`, `docker`, `awscli2`, and many others) live in
`common.nix` and are shared across all platforms.

## Editor Configuration

- `home-manager/lib/code-editor-user-settings.nix` is the shared source for VS Code user settings.
- `common.nix` and `home-darwin.nix` install those settings and Copilot prompt files into each editor's user config directory.
- Custom agents and skills live in `ai-tools/agents/` and `ai-tools/skills/` as the single source of truth, with a
  Claude Code marketplace manifest in `ai-tools/.claude-plugin/`.
- Home Manager deploys skills and agents to `~/.config/claude/{agents,skills}` and `~/.config/copilot/{agents,skills}`
  for Claude Code and the Copilot CLI. For VS Code Copilot Chat, generated `*.prompt.md` bridges are installed under
  `prompts/skills/` and `prompts/agents/` — available on-demand via `/` rather than as always-on instructions. The
  shells export `CLAUDE_CONFIG_DIR` and `COPILOT_HOME` pointing at those XDG paths.
- `.devcontainer/devcontainer.json` is the bootstrap layer for container sessions before the Home Manager profile is
  applied.
- `.vscode/settings.json` and `.vscode/extensions.json` are repo-workspace-specific and should stay focused on the Nix
  formatter, language server, and extension recommendations.
- If a setting should follow you across machines, keep it in Home Manager. If it applies only to this repository, keep
  it in `.vscode`.

## Modules

### Audio Module: pulseaudio

Disables legacy PulseAudio and enables PipeWire with ALSA, PulseAudio compatibility, and Real-Time Kit support.

## Service Tasks

```bash
task service-status SERVICE=pipewire.service   # check a user service via systemctl --user
task logs SERVICE=pipewire.service             # tail logs via journalctl --user
```

## Maintenance

```bash
task update && task switch          # keep the system updated
task gc                             # clean up old generations
task optimize                       # optimize the Nix store
task generate:agent-instructions    # re-render agent-defaults.md into chezmoi files
task check:agent-instructions       # verify chezmoi files match the source (also in CI)
task check:copilot-instructions     # verify .github/copilot-instructions.md stays in sync
```

## Git Hooks

- Run `task hooks:install` once per clone to configure Git to use the tracked hooks in `.githooks/`.
- The pre-commit hook runs `task lint:nix` inside `nix shell nixpkgs#go-task nixpkgs#statix nixpkgs#deadnix`, which
  includes `check:copilot-instructions` and `check:agent-instructions`.
- Hooks are local Git configuration and do not enable themselves automatically for other clones.

## Platform Notes

### macOS

- Uses `nix-darwin` for system settings and Home Manager for user configuration.
- Shell configuration is shared with Linux where possible, with Darwin-specific overrides in `home-manager/home-darwin.nix`.
- Firefox is installed via Homebrew casks in `hosts/darwin/default.nix`; the Stylix Firefox target is disabled on macOS.

### WSL

- Uses `NixOS-WSL` as the base system module.
- `programs.nix-ld` is enabled on the WSL host so VS Code Remote / `.vscode-server` binaries have a compatible runtime
  on NixOS.
- The WSL Home Manager profile deploys `starship.toml` to Windows and bootstraps starship + PowerShell 7 via winget.
  Chezmoi owns the PowerShell profile.
- `install.sh` detects WSL automatically, enables interop in `/etc/wsl.conf`, and runs the Windows bootstrap. On plain
  Linux, the Windows steps are skipped.
- `task wsl-bootstrap-windows` bootstraps Windows-side Scoop buckets, installs the configured Nerd Font, and updates
  Windows Terminal to use the same font. The script auto-registers the WSL interop binfmt handler if missing.
- First-time switches should use a path-based flake reference (`path:$PWD#wsl`) until all new files are tracked by Git.

### Windows (native)

- `task windows-bootstrap` is the native Windows entry point (runs via PowerShell, no WSL required).
- After bootstrap, use `task chezmoi-init` and `task chezmoi-apply` to deploy dotfiles.
- chezmoi manages the PowerShell profile, flameshot config, agent instructions, `~/.local/bin` scripts, and other
  dotfiles on Windows since home-manager is unavailable.
- Flameshot uses Alt+Shift+3/4 for screenshots on Windows (Ctrl+Shift+3/4 on Linux/macOS).

## Customization

1. Update user information in the relevant host or Home Manager profile.
2. Add or remove packages in `home-manager/common.nix` (shared) or the appropriate profile.
3. Edit `chezmoi/dot_config/instructions/agent-defaults.md` for agent instruction changes, then run
   `task generate:agent-instructions` and commit the result.
4. Edit `chezmoi/dot_config/colors/monokai.toml` to change the color palette — Nix, Stylix, and chezmoi all read from
   this single file.
5. Adjust module configurations as needed.

## GitHub Actions CI

- GitHub Actions validates Linux and macOS targets by building flake outputs.
- The WSL target is validated by building `nixosConfigurations.wsl`.
- GitHub-hosted runners do not provide a real WSL2 runtime, so end-to-end WSL boot tests require a self-hosted Windows
  runner with WSL2 enabled.
- The workflow lives at `.github/workflows/nix-validation.yml`.
