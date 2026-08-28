# Nix Configuration

Jeremy's personal system configuration. A **single flake** manages NixOS, NixOS-WSL, and macOS
(via Home Manager, NixOS-WSL, and nix-darwin), while **chezmoi** layers dotfiles on top — including
on Windows-native hosts that have no Nix at all. Both halves live in this one repository.

Everything is driven through [`task`](https://taskfile.dev) so you never hand-assemble
`nixos-rebuild` / `darwin-rebuild` / `home-manager` invocations. The taskfile detects your platform
and routes to the right configuration automatically.

## Highlights

- **One flake, three platforms** — `darwin`, `linux`, and `wsl` hosts share a common Home Manager base,
  with standalone Home Manager profiles for non-NixOS Linux, WSL distros, and devcontainers.
- **Nix + chezmoi hybrid** — Nix owns packages and system state; chezmoi owns dotfiles and reaches the
  places Nix can't (native Windows, `/etc` on non-flake hosts).
- **TOML as single source of truth** — the color palette, SSH host inventory, shell aliases, and MIME
  defaults are each defined once in TOML and read at Nix eval time (see [TOML-sourced config](#toml-sourced-config)).
- **Safety nets** — every switch is preceded by a btrfs snapshot where snapper exists, and `~/.config`
  plus `~/.local` back up daily to Google Drive (see [Backups & snapshots](#backups--snapshots)).
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

### Secrets bootstrap

Secrets are SOPS-encrypted with an age key that is **not** in this repo. On a new machine run
`scripts/provision-secrets.sh` (or `install.sh`, which calls it) to place `~/.config/sops/age/keys.txt`
**before** the first switch — sops-nix needs the key at activation time. See [Secrets](#secrets).

## Everyday commands

```bash
task build            # build only, no activation
task switch           # build + activate (auto-detects host)
task home-switch      # Home Manager only, no system rebuild
task check            # validate the flake

task fmt              # format nix files (alejandra)
task fmt:all          # every formatter: nix, markdown, shell, python, toml
task lint             # every linter (see Formatting & linting)

task upgrade          # update flake inputs + switch + refresh the agent CLIs
task update           # update flake inputs only
task agents:update    # update the off-nixpkgs agent CLIs only
task gc               # garbage-collect old generations
task optimize         # deduplicate the Nix store
```

Override platform detection on any task with `HOST=<target>`, e.g. `task switch HOST=linux`.
Shortcuts `task linux` / `task darwin` / `task wsl` are aliases for the same.

### What a switch actually runs

`task switch` (and `home-switch` / `upgrade`) is more than a rebuild. In order:

1. **`_snapshot-pre`** — a best-effort pre-change btrfs snapshot via `btrfs-safety-snapshot`
   (see [Backups & snapshots](#backups--snapshots)). No-op without snapper; bypass with `SKIP_SNAPSHOT=1`.
2. **`_record-nix-config-dir`** — writes `$PWD` to `~/.local/state/chezmoi/nix-config-dir` so chezmoi
   and Home Manager find the checkout wherever it lives.
3. **`_chezmoi-ensure`** — `chezmoi apply`, with git forced non-interactive so a stalled credential
   prompt on an external can't hang the switch.
4. **`fmt` + `generate:agent-instructions`** — format Nix and re-render the agent instruction files.
5. The rebuild itself — `nixos-rebuild` / `darwin-rebuild` / standalone `home-manager`, routed by host.
6. On plain (non-NixOS) Linux, `ensure-nix-zsh-shell` fixes the login shell to Home Manager's zsh.
   `task upgrade` additionally runs `update-agent-clis`.

### Platform auto-detection

| Condition | Detected host |
|---|---|
| macOS (`uname` = Darwin) | `darwin` |
| Linux, hostname `nixos` or `wsl` | `wsl` |
| Linux, hostname `linux` | `linux` |
| WSL Debian / Ubuntu (`/proc/version` + `/etc/os-release`) | `debian-wsl` / `ubuntu-wsl` |
| `INSIDE_DEVCONTAINER` set | `vscode@devcontainer[-aarch64]` |
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
modules/                    Shared NixOS system modules (e.g. audio/pulseaudio.nix)
home-manager/               Shared user config — common.nix (packages), per-platform entrypoints,
                              zsh.nix, starship.nix, lib/ (renderers & helpers), modules/, profiles/
chezmoi/                    chezmoi-managed dotfiles for every platform (incl. Windows), plus
                              ~/.local/bin helper scripts and run_once / run_onchange provisioning
ai-tools/                   Skills, agents, slash commands, and the Claude Code plugin marketplace
secrets/                    SOPS-encrypted secrets (age); never plaintext — see sec-sops-encrypt skill
scripts/                    Provisioning, switch-tolerance, and CI helper scripts
tests/                      Test suites for the Kion AWS credential cache (bash + python)
docs/                       Design notes (e.g. agent-token-cost-levers.md)
TODO.md                     Working backlog
.github/workflows/          CI: nix-validation, secrets-scan, update-flake
```

## Available hosts

Flake-managed:

- **darwin** — macOS via nix-darwin + Home Manager. (`ICFGG241C3Y03` is a legacy alias for the same config.)
- **linux** — NixOS with KDE Plasma, development tooling, and desktop packages.
- **wsl** — NixOS-WSL. `hosts/wsl/default.nix` sets the hostname to `wsl` so auto-detection works after
  the first switch.

Standalone `homeConfigurations` (no NixOS underneath): `jhettenh@linux`, `jhettenh@nixos-wsl`,
`jhettenh@debian-wsl`, `jhettenh@ubuntu-wsl`, and `vscode@devcontainer[-aarch64]`.

**Not every managed machine is in the flake.** `tifa` is a CachyOS (Arch) box whose system config lives
outside this repo; `chezmoi/run_once_provision-tifa-etc.sh.tmpl` reproduces its hand-applied `/etc` fixes
(NVIDIA suspend/RTD3, a Bluetooth sleep hook, `nvidia-powerd`) so a reinstall doesn't lose them. It is
hostname-gated and a no-op everywhere else.

> **First WSL switch:** before your new local files are tracked by Git, use a path-based flake reference:
>
> ```bash
> NIX_CONFIG="experimental-features = nix-command flakes" sudo nixos-rebuild switch --flake "path:$PWD#wsl"
> ```
>
> After that, the `task wsl` / `task home-switch` aliases work normally.

## Home Manager profiles

Shared dev tools (`git`, `gh`, `go`, `neovim`, `ripgrep`, `fzf`, `jq`, `docker`, `awscli2`, and many more)
live in `common.nix` and apply everywhere. Linux layers two profiles on top:

- **Development** (`profiles/development-linux.nix`) — gnumake/cmake, Node.js, kubectl, and VS Code
  (non-WSL) with a curated extension set plus per-language **VS Code profiles** for Go, Python, Java,
  and Node. Profiles don't inherit default-profile settings, so each re-uses the shared settings from
  `lib/code-editor-user-settings.nix`.
- **Desktop** (`profiles/desktop-linux.nix`) — Firefox + Vivaldi (default), VLC/mpv, Discord/Slack,
  LibreOffice/Obsidian/KeePassXC, GIMP/Inkscape/Flameshot, declarative MIME defaults, and the KDE Plasma
  layout (four virtual desktops in one row, a panel pinned to screen 0, pinned launchers, Dolphin as the
  file manager).

**GPU-dependent packages are deliberately not Nix-managed on generic Linux.** `kitty` and `zoom-us` link
against Nix's glibc and can't safely load a host Mesa/NVIDIA driver, so they are gated behind
`isNixos` (set for the NixOS `linux` host, where `/run/opengl-driver` exists). Elsewhere install them
natively — `kitty` is installed automatically by
`chezmoi/run_onchange_provision-linux-host.sh.tmpl` (every host needs it: home-manager wires a KDE
global shortcut and the default-terminal association straight to `kitty.desktop`), `zoom-us` via
`flatpak install --user flathub us.zoom.Zoom` — and Home Manager still owns their config and Stylix
theming. Flatpak export dirs are added to `XDG_DATA_DIRS` so `xdg-open` can resolve Flatpak `.desktop`
IDs in a non-login session.

Vivaldi's Chromium sandbox needs an unprivileged user namespace since the setuid sandbox helper can
never work from the read-only Nix store; on Ubuntu/Debian-family hosts (where AppArmor denies that by
default to anything without an explicit profile) the same provisioning script installs a scoped
AppArmor profile granting it, gated on AppArmor actually being the host's active LSM.

## Chezmoi dotfile management

Chezmoi's source directory is `chezmoi/` in this repo. `task chezmoi-init` writes
`~/.config/chezmoi/chezmoi.toml` to point there; on Linux and macOS, Home Manager activation does the
same automatically on every `task switch`.

```bash
task chezmoi-apply              # apply dotfiles to your home directory
task chezmoi-add FILE=~/.somerc # bring a file under management
task chezmoi-diff               # preview pending changes
task chezmoi-edit FILE=~/.somerc
```

Ignore rules are split across two files:

- `.chezmoiignore.tmpl` — the Go-templated rules. Platform splits (agent instruction files are ignored on
  Linux/macOS because Home Manager owns them via Nix store symlinks; Windows gets everything, since Home
  Manager isn't available there), plus **deploy-only-if-present** rules: the work-repo directives, the
  KeePassXC theme `modify_` script, and `toggle-browser` only deploy on hosts that already have the
  corresponding checkout, ini, or OS.
- `.chezmoiignore` — static rules, mainly Python bytecode and tool caches. chezmoi does not read
  `.gitignore`, so a stray `__pycache__` beside a managed `.py` would otherwise be deployed.

Externals (`.chezmoiexternal.toml.tmpl`, `refreshPeriod = 720h`) pull the borland502 Go CLI sources into
`~/.local/src` and the upstream AI-tooling repos into `~/.local/src/ai-tools/`.

On Windows, `run_onchange_deploy-vscode-instructions.ps1.tmpl` additionally copies the Copilot
instructions into `%APPDATA%\Code\User\prompts\`, where native VS Code reads them. (It's a no-op
elsewhere.)

## TOML-sourced config

Several settings are authored once in TOML under `chezmoi/dot_config/` and parsed at Nix eval time with
`builtins.fromTOML`, so chezmoi and Nix can never disagree about them:

| Source | Consumed by | Drives |
|---|---|---|
| `colors/monokai.toml` | `lib/colors.nix`, `common.nix` | Stylix `base16Scheme`, Starship, zsh, PowerShell |
| `secrets/hosts.toml` | `modules/sops.nix` | SOPS-encrypted host inventory; decrypted to `~/.config/ssh/hosts.toml` and rendered into `~/.ssh/config.d/hosts` at activation |
| `zsh/aliases.toml` | `zsh.nix` | shell aliases |
| `mimeapps/defaults.toml` | `profiles/desktop-linux.nix` | `xdg.mimeApps` default handlers |

### Color palette

The Monokai Spectrum palette is the oldest and widest-reaching of these:

- Fed to Stylix as the `base16Scheme`, which themes bat, btop, fzf, kitty, Starship, Vim, VS Code, GTK,
  and KDE automatically
- Referenced by `starship-settings.nix`, `zsh.nix`, `lib/vivid-theme.nix`, and the per-platform Home
  Manager entrypoints
- Deployed to `~/.config/colors/monokai.toml` by chezmoi on all platforms, and read by the PowerShell
  profile's `$Monokai` table for PSReadLine and fzf theming

## Secrets

`secrets/` holds SOPS-encrypted files (age). `home-manager/modules/sops.nix` decrypts them at activation:

| File | Contents |
|---|---|
| `ops-agent.yaml` | Jira / Confluence / ops-agent tokens |
| `arr.yaml` | Sonarr / Prowlarr API keys |
| `rclone-gdrive.json` | Google Drive OAuth *client* credentials (the per-device token stays local) |
| `gkion.toml` | Kion API settings — decrypted whole-file at activation |
| `technitiumdns-cli.toml` | Technitium DNS CLI config — decrypted whole-file at activation |

sops-nix extracts individual keys, but tools that want a whole config file (gkion, technitiumdns) get a
full-file decrypt in an activation script instead.

> **Bootstrap order matters.** The age key must exist at `~/.config/sops/age/keys.txt` *before* the first
> switch — run `scripts/provision-secrets.sh` first. Without it, activation used to skip secrets silently;
> it now fails loudly instead. Use the `sec-sops-encrypt` skill when adding or rotating a secret, and
> `task lint:secrets` (gitleaks) to scan history.

## Backups & snapshots

**Pre-switch btrfs snapshots.** `~/.local/bin/btrfs-safety-snapshot` takes a snapper `root` snapshot
before any activation, filling the gap snap-pac leaves (it brackets pacman transactions, not nix
switches). The `root` subvolume is `/`, so `/nix` — and therefore the pre-switch store closure — is
captured, which is exactly what a dangling-profile recovery needs. It is a no-op without a snapper `root`
config (macOS, WSL, non-snapper Linux) and skips non-interactively when sudo isn't cached, but is
fail-closed otherwise: a real snapshot failure aborts the switch. Bypass with `SKIP_SNAPSHOT=1`.
Run it standalone before any risky manual change.

**Daily Google Drive backup.** `~/.local/bin/sync-to-gdrive` backs `~/.config` and `~/.local` up to an
rclone `gdrive:` remote (no mount required). It is additive — remote files are never deleted just because
they're absent locally — while junk that was previously backed up gets purged. Secrets, browser password
stores, agent session transcripts, caches, and large regenerable trees are filtered out; `--copy-links`
resolves Nix store symlinks so real content is preserved.

```bash
setup-gdrive-remote                 # once per host: creates/reconnects the rclone remote (needs a TTY)
sync-to-gdrive --dry-run            # preview
sync-to-gdrive --allow-local-delete # UNSAFE: restore direction (gdrive -> local)
```

`home-manager/modules/gdrive-sync.nix` schedules the backup direction — a systemd user timer on Linux
(`OnCalendar` daily with `Persistent=true` so a run missed while the machine was off catches up, plus a
randomized delay) and a launchd agent on darwin.

```bash
systemctl --user list-timers gdrive-sync.timer     # Linux
journalctl --user -u gdrive-sync.service
launchctl list org.nix-community.home.gdrive-sync  # darwin (log: ~/.cache/gdrive-sync.launchd.log)
```

## Helper scripts

Deployed by chezmoi to `~/.local/bin` (on `PATH`, ahead of the Nix profile):

| Script | Purpose |
|---|---|
| `kac` | Kion AWS credential cache proxy — **source** it: `source ~/.local/bin/kac ensure` |
| `kion-aws-refresh` / `kion-aws-cache` | fetch and cache temporary AWS credentials from the Kion API (tested in `tests/`) |
| `update-agent-clis` | install/update Claude Code and the GitHub Copilot CLI via their vendor installers |
| `pkg-install` | install via the host's native package manager (pacman/apt/dnf/zypper/brew), not Nix |
| `ensure-nix-zsh-shell` | point the login shell at Home Manager's zsh on non-NixOS Linux |
| `btrfs-safety-snapshot` | pre-change snapper snapshot |
| `sync-to-gdrive` / `setup-gdrive-remote` | Google Drive backup and its one-time remote setup |
| `cache-scan` | terse scan of recent agent session logs |
| `jira-get` / `jira-my-tickets` / `confluence-get` / `confluence-page` | Atlassian REST helpers |
| `gh-graphql` / `gh-run-logs` / `monitor-gh-run` | file-backed GraphQL queries and Actions run monitoring |
| `toggle-browser` | toggle the macOS default browser |

The Kion credential helpers are the one part of this repo with real test coverage; run them directly:

```bash
bash tests/test_kion_aws_cache.sh
python3 tests/test_kion_aws_refresh.py
```

## AI tooling (skills + agents)

Custom skills, agents, and instructions live in [`ai-tools/`](ai-tools/) as the single source of truth,
modeled on the [obra/superpowers](https://github.com/obra/superpowers) layout:

```text
ai-tools/
├── .claude-plugin/   Marketplace + plugin metadata registering nix-config-tools
├── agents/           Custom sub-agents (*.agent.md)
├── commands/         Slash commands for routine chores (flake-refresh, jira-digest, reconcile-audit)
├── scripts/          Hook loggers, cache compaction, the ops-agent CLI, and the AWS MCP wrapper
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

Skills and agents must stay **model-agnostic**: tier aliases (`opus`/`sonnet`/`haiku`) in `model:`
frontmatter, never versioned model IDs. `task check:model-agnostic` (part of `task lint:nix` and the
pre-commit hook) enforces it. The sanctioned pin points are the `ANTHROPIC_DEFAULT_*_MODEL` block in
`chezmoi/dot_claude/settings.json`, the Copilot default in `common.nix`, and the tier map in
`agent-reference.md`.

The `registerClaudeMarketplaces` activation hook idempotently registers two marketplaces in
`~/.config/claude/settings.json`: `nix-config-dev` (this repo's `ai-tools`, enabling `nix-config-tools`)
and `anthropic-agent-skills` (a chezmoi external at `~/.local/src/ai-tools/anthropic-skills`, enabling
`document-skills` and `claude-api`). The proprietary `document-skills` plugin is loaded directly from
the upstream checkout and never copied into this repo.

### Agent CLIs are not in the flake

Claude Code and the GitHub Copilot CLI are deliberately **not** Nix-managed. A Nix store install is
read-only, so the CLI's own `update` can't refresh it — the Copilot copy froze at 1.0.26, and a stale
build's hardcoded subagent model allowlist rejects current models even when the interactive picker
offers them. Both install into `~/.local` via their vendor installers (`update-agent-clis`, invoked by
`run_onchange_install-agent-clis.sh.tmpl`, `task agents:update`, and the tail of `task upgrade`), and
`~/.local/bin` is ahead of the Nix profile on `PATH`.

The `nixpkgs-unstable` overlay still exists, but now only for Electron apps (VS Code, Slack, Discord,
Obsidian) and Nix-managed browsers, which need current Chromium security fixes. Vivaldi is overridden
with `proprietaryCodecs = true` — without it the bundled free codec triggers an auto-download that fails
to load and crashes Vivaldi on launch.

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
| `log-skill.sh` | Skill `PostToolUse` (Claude), skill hook (Copilot) | skill invocations → `session_<id>.skills.log` |
| `log-instructions.sh` | `InstructionsLoaded` (Claude) | loaded instruction files → `session_<id>.instructions.log` |
| `claude-cache-stats` | `SessionEnd` | prompt-cache-hit summary → `cache-stats.log` |

`compress-old-cache` (session-end hook + daily timer) zstd-compresses logs older than a day (or over
1 MB) and prunes anything untouched for ~1.5 years. The same directory also carries `aws-mcp-server`
and `ops-agent.py` — the implementation behind the `ops-agent` CLI, which is exposed as a wrapper
script rather than run directly.

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
  `common.nix` deploys them everywhere via `programs.vscode.userSettings`, `home-wsl.nix` reuses them for
  the `.vscode-server` (VS Code Remote) settings on WSL, and the per-language profiles in
  `profiles/development-linux.nix` re-apply them so a profile doesn't start from stock VS Code.
- `.devcontainer/devcontainer.json` bootstraps container sessions before the Home Manager profile applies.
- `.vscode/` is repo-workspace-specific (Nix formatter, language server, extension recommendations) and
  should stay focused on this repository.
- Rule of thumb: settings that should follow you across machines belong in Home Manager; settings that
  apply only to this repo belong in `.vscode/`.

## Modules

System modules (`modules/`, imported by NixOS hosts):

- **Audio (`modules/audio/pulseaudio.nix`)** — disables legacy PulseAudio and enables PipeWire with ALSA,
  PulseAudio compatibility, and Real-Time Kit support.

Home Manager modules (`home-manager/modules/`):

- **`sops.nix`** — user-level secret decryption at activation (see [Secrets](#secrets)).
- **`gdrive-sync.nix`** — the scheduled Google Drive backup (see [Backups & snapshots](#backups--snapshots)).

Inspect user services through tasks:

```bash
task service-status SERVICE=pipewire.service   # systemctl --user
task logs SERVICE=pipewire.service             # journalctl --user
```

## Platform notes

- **macOS** — nix-darwin for system settings, Home Manager for user config; Firefox via Homebrew casks
  (the Stylix Firefox target is disabled here). `scripts/darwin-switch-tolerant.sh` tolerates
  VPN-blocked cask downloads.
- **NixOS (`linux`)** — the only host where `isNixos = true`, which unlocks the GPU-dependent packages
  guarded in `profiles/desktop-linux.nix`.
- **Plain Linux (non-NixOS)** — standalone Home Manager via `jhettenh@linux`; the login shell is fixed by
  `ensure-nix-zsh-shell`, and GPU-dependent apps come from the distro (`kitty` auto-installed by the
  provisioning script, others via `pkg-install`) or Flatpak.
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
4. Edit the TOML sources in `chezmoi/dot_config/` — `colors/monokai.toml` (palette),
   `zsh/aliases.toml`, `mimeapps/defaults.toml` — and both Nix and chezmoi pick the change up.
5. Edit the ssh inventory with `sops secrets/hosts.toml`. It is encrypted because this repo
   is public and the inventory maps the whole home network. Unlike the files above it is
   **not** read at flake-eval time — eval is pure and cannot decrypt — so it is decrypted to
   `~/.config/ssh/hosts.toml` and rendered into `~/.ssh/config.d/hosts` during activation.

## Formatting & linting

```bash
task fmt:all          # every formatter: alejandra, markdownlint --fix, shfmt -i 0, ruff, taplo
task fmt              # nix only (alejandra)
task fmt:md fmt:sh fmt:py fmt:toml

task lint             # every linter below
task lint:nix         # statix + deadnix + check:copilot-instructions / agent-instructions /
                      #   instruction-size / model-agnostic  (this is the pre-commit chain)
task lint:md          # markdownlint-cli2, 120-char lines
task lint:sh          # shellcheck + shfmt -d
task lint:py          # ruff check
task lint:yaml        # yamllint
task lint:toml        # taplo lint
task lint:secrets     # gitleaks over repo history
```

`ai-tools/` and `secrets/` are excluded from most of these — the former is ingested upstream content, the
latter is ciphertext that isn't valid TOML/YAML.

## Maintenance & CI

```bash
task update && task switch        # keep the system current (CI also opens a weekly update PR)
task upgrade                      # the same, plus the off-nixpkgs agent CLIs
task gc / task optimize           # clean up generations / dedupe the store
task generate:agent-instructions  # re-render agent files after editing the source
task check:instruction-size       # guard the always-on prefix against bloat
```

Run `task hooks:install` once per clone to use the tracked hooks in `.githooks/`. The pre-commit hook
runs `task lint:nix` (statix, deadnix, and the `check:agent-instructions` / `check:copilot-instructions` /
`check:instruction-size` / `check:model-agnostic` checks).

CI validates Linux and macOS by building flake outputs and the WSL target by building
`nixosConfigurations.wsl` (GitHub runners have no real WSL2, so end-to-end boot tests need a self-hosted
Windows runner). `secrets-scan.yml` runs gitleaks. `update-flake.yml` bumps `flake.lock` weekly
(Mondays 05:17 UTC, or on demand) and opens a labeled PR. Note: PRs opened with the default
`GITHUB_TOKEN` don't trigger validation automatically — close/reopen or push to the branch to run CI
before merging.

## Credits

This project's own code is MIT-licensed ([LICENSE](LICENSE)). Ingested upstream skills under
`ai-tools/skills/` and `ai-tools/skills-stack/` retain their original licenses and `origin:` frontmatter;
skills without an `origin:` line (`flow-reconciliation`, `gh-graphql-jq-pipelines`, the `ops-agent` /
`ops-cache-scan` / `ops-chezmoi` / `ops-confluence` / `ops-nix-pitfalls` set, `sec-credentials`,
`sec-sops-encrypt`, `shell-pitfalls`, and others) are original to this repo. `ops-repo-scan` is
community-sourced (see its frontmatter).

| Upstream | License | Borrowed |
|---|---|---|
| [anthropics/skills](https://github.com/anthropics/skills) | Apache 2.0 / proprietary | `claude-api`, `document-skills` (loaded via marketplace, not redistributed) |
| [obra/superpowers](https://github.com/obra/superpowers) | MIT | `flow-*`, `git-worktrees`, `git-finish-branch`, `git-request-review` |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | `golang-*`, `python-*`, `springboot-*`, `postgres-patterns`, `database-migrations`, `e2e-testing`, `github-ops`, `ops-jira-integration`, `git-workflow`, `sec-review` |
| [github/awesome-copilot](https://github.com/github/awesome-copilot) | MIT | `github-actions`, `react18-batching-patterns` |
| [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) | MIT | `defuddle`, `json-canvas` |
| [wshobson/agents](https://github.com/wshobson/agents) | MIT | `javascript-testing-patterns`, `modern-javascript-patterns`, `nodejs-backend-patterns`, `typescript-advanced-types` |
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
