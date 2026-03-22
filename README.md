# Nix Configuration

Jeremy's personal Nix configuration with modular organization for NixOS, WSL, and macOS via Home Manager, NixOS-WSL, and nix-darwin.

## Structure

```text
├── flake.nix                         # Flake inputs and platform outputs
├── flake.lock                        # Locked flake input revisions
├── scripts/
│   └── wsl/
│       ├── bootstrap-windows.sh      # WSL entrypoint for Windows bootstrap
│       └── bootstrap-windows.ps1     # Windows-side Scoop/font/bootstrap logic
├── taskfile.yaml                     # Common build, switch, and maintenance tasks
├── hosts/                            # System-level host definitions
│   ├── darwin/default.nix            # nix-darwin system configuration
│   ├── linux/default.nix             # NixOS module for the linux target
│   ├── linux/hardware-configuration.nix
│   └── wsl/default.nix               # NixOS-WSL host configuration
├── modules/
│   └── audio/pulseaudio.nix          # Shared audio/PipeWire module
├── home-manager/
│   ├── common.nix                    # Shared Home Manager base config
│   ├── home.nix                      # Linux Home Manager entrypoint
│   ├── home-darwin.nix               # macOS Home Manager entrypoint
│   ├── home-wsl.nix                  # WSL Home Manager entrypoint
│   ├── zsh.nix                       # Shared shell configuration
│   ├── starship.nix                  # Shared prompt configuration
│   ├── profiles/
│   │   ├── development-linux.nix     # Linux development packages
│   │   └── desktop-linux.nix         # Linux desktop packages
│   └── config/
│       ├── colors/monokai.base24.yaml
│       ├── copilot/
│       └── kitty/kitty.conf
├── .devcontainer/devcontainer.json   # Devcontainer bootstrap for Home Manager outputs
├── .github/workflows/nix-validation.yml
└── .vscode/                          # Repo-local VS Code recommendations/settings
```

## Quick Start

### Initial Setup

1. Clone this repository to `~/.config/nix`
2. Update the host-specific settings for your machine
3. Apply the matching system or home configuration for your platform

### Building and Switching

Use the included taskfile for common operations:

```bash
# Build the configuration
task build

# Build and switch to the configuration
task switch

# Build for the Linux target explicitly
task switch HOST=linux

# Update flake inputs
task update

# Garbage collect old generations
task gc

# Format nix files
task fmt

# Check for errors
task check
```

### WSL Bootstrap

If WSL is not yet running this configuration, use a path-based flake reference for the first switch so newly added local files are included even before they are tracked by Git:

```bash
cd ~/nix-config
NIX_CONFIG="experimental-features = nix-command flakes" sudo nixos-rebuild switch --flake "path:$PWD#wsl"
```

After the initial switch, you can continue using the WSL task alias:

```bash
task wsl
task home-switch HOST=wsl
task wsl-bootstrap-windows
```

### macOS Setup

For macOS, this repo uses `nix-darwin` plus Home Manager. The primary Darwin target in this repo is `darwin`.

Use the platform-aware tasks or the Darwin-specific aliases:

```bash
task build
task switch
task switch HOST=darwin
task darwin-build
task darwin-switch
```

The macOS setup in this repo includes:

- A dedicated Darwin host at `hosts/darwin/default.nix`
- A dedicated Home Manager profile at `home-manager/home-darwin.nix`
- Shared shell and prompt configuration through Zsh and Starship
- nix-darwin and Home Manager integration through the flake

### Available Hosts

These host names are starter placeholders for new installs. They are intentionally generic so the initial flake and task workflow works out of the box; rename the target names and underlying `networking.hostName` values later if you want machine-specific identities. The older machine-specific macOS target `ICFGG241C3Y03` remains as a compatibility alias to the same Darwin configuration.

- **darwin**: Primary macOS configuration using nix-darwin and Home Manager
- **linux**: Primary Linux configuration with KDE Plasma, development tooling, virtualization, and desktop packages
- **wsl**: WSL configuration using NixOS-WSL

## Modules

### Audio Module: pulseaudio

Disables legacy PulseAudio and enables PipeWire with ALSA, PulseAudio compatibility, and Real-Time Kit support.

## Home Manager Profiles

### Development Profile

Includes:

- Development tools (VS Code, Neovim, Git)
- Programming languages (Python, Node.js, Go, Rust)
- Container tools (Docker, Podman)
- Cloud tools (kubectl, Terraform, AWS CLI)

### Desktop Profile

Includes:

- Web browsers and GUI tools
- Media applications (VLC, mpv)
- Communication tools (Discord, Slack)
- Productivity software (LibreOffice, Obsidian)

## Editor Configuration

- `home-manager/common.nix` is the source for persistent VS Code user defaults applied through Home Manager.
- `.devcontainer/devcontainer.json` is only the bootstrap layer for container sessions before the Home Manager profile is applied.
- `.vscode/settings.json` and `.vscode/extensions.json` are the repository-specific layer and should stay focused on workspace behavior such as the Nix formatter, language server, and extension recommendations.
- If a setting should follow you across machines, keep it in Home Manager. If it should apply only to this repository, keep it in `.vscode`.

## Service Tasks

- `task service-status SERVICE=pipewire.service` checks a specific user service.
- `task logs SERVICE=pipewire.service` tails logs for a specific service.
- These tasks are generic wrappers around `systemctl --user` and `journalctl`; they are not specific to rclone.

## Theming

The configuration uses Stylix for system-wide theming with the Monokai color scheme.

## Platform Notes

### macOS

- Uses `nix-darwin` for system settings and Home Manager for user configuration
- Shell configuration is shared with Linux where possible, with Darwin-specific overrides in `home-manager/home-darwin.nix`
- Determinate Nix compatibility is handled in the Darwin configuration

### WSL

- Uses `NixOS-WSL` as the base system module
- Uses a dedicated WSL Home Manager profile at `home-manager/home-wsl.nix`
- Enables `programs.nix-ld` on the WSL host so VS Code Remote / `.vscode-server` binaries have a more compatible runtime on NixOS
- First-time switch commands should use a path-based flake reference until all new files are tracked by Git
- The WSL profile also bridges shared prompt config into Windows by writing PowerShell profiles and a Windows `starship.toml`, then bootstrapping `starship` and PowerShell 7 with `winget` when available
- `task wsl-bootstrap-windows` bootstraps Windows-side Scoop buckets, installs the configured Nerd Font, and updates Windows Terminal to use the same font

## Maintenance

- Run `task update && task switch` regularly to keep the system updated
- Use `task gc` to clean up old generations
- Use `task optimize` to optimize the Nix store

## Customization

To customize for your setup:

1. Update user information in the relevant host or Home Manager profile
2. Update the user and shell settings in the relevant host or home-manager profile
3. Add or remove packages in the appropriate profile
4. Adjust module configurations as needed

## Migration from Old Structure

If migrating from the old monolithic configuration:

1. Backup your current configuration
2. Copy host-specific settings to the new structure
3. Test the build with `task check` and `task build`
4. Switch when ready with `task switch`

## macOS Notes

- Firefox is installed on macOS via Homebrew casks in `hosts/darwin/default.nix`.
- The Stylix Firefox target remains disabled in `home-manager/home-darwin.nix`, so Firefox theming integration is intentionally off on macOS for now.
- `ncdu` is not currently included in the shared package list in `home-manager/common.nix`.
- The previous LLVM/Zig build warning from 2025 is no longer confirmed by current dry-run checks: on 2026-03-20, `nix build nixpkgs#ncdu --dry-run` resolved via fetchable artifacts, and `nix build nixpkgs#firefox --dry-run` resolved to fetched artifacts plus small wrapper derivations rather than the older large local toolchain build pattern.

## Validation Notes

### Darwin Validation

- `darwin-rebuild` is expected to be available from the active system profile
- Platform-aware tasks in `taskfile.yaml` detect Darwin and route to `darwin-rebuild`
- Home Manager is integrated into the Darwin flake output rather than managed separately

### GitHub Actions CI

- GitHub Actions can validate Linux and macOS targets directly by building flake outputs.
- The WSL target can be validated in CI by building `nixosConfigurations.wsl`, which checks the NixOS-WSL configuration itself.
- GitHub-hosted runners do not provide a real WSL2 runtime session, so end-to-end WSL boot or runtime tests require a self-hosted Windows runner with WSL2 enabled.
- The workflow for this repository lives at `.github/workflows/nix-validation.yml`.
