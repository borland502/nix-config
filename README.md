# Nix Configuration

Jeremy's personal Nix configuration with modular organization for NixOS, WSL, and macOS via Home Manager, NixOS-WSL, and nix-darwin.

## Structure

```text
├── flake.nix                    # Main flake configuration
├── taskfile.yaml               # Task automation for common operations
├── hosts/                      # Host-specific configurations
│   ├── common/                 # Shared configurations
│   │   ├── global.nix         # Common system settings
│   │   └── users.nix          # User configurations
│   ├── darwin/                # macOS host configuration
│   ├── krile/                 # Krile laptop configuration
│   └── wsl/                   # WSL host configuration
├── modules/                    # Reusable NixOS modules
│   ├── desktop/               # Desktop environment modules
│   │   └── plasma.nix         # KDE Plasma configuration
│   ├── audio/                 # Audio system modules
│   │   └── pulseaudio.nix     # PulseAudio configuration
│   ├── virtualization/        # Virtualization modules
│   │   └── libvirt.nix        # Libvirt/QEMU configuration
│   └── services/              # Service modules
│       └── rclone.nix         # Reusable rclone mount service
└── home-manager/              # Home Manager configurations
    ├── profiles/              # User profiles
    │   ├── development.nix    # Development tools and configuration
    │   └── desktop.nix        # Desktop applications
    ├── zsh.nix               # Zsh shell configuration
    ├── starship.nix          # Starship prompt configuration
    └── plasma.nix            # KDE Plasma user configuration
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

# Build for a specific host
task switch HOST=krile

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
```

### macOS Setup

For macOS, this repo uses `nix-darwin` plus Home Manager. The configured Darwin host in this repo is `ICFGG241C3Y03`.

Use the platform-aware tasks or the Darwin-specific aliases:

```bash
task build
task switch
task darwin-build
task darwin-switch
```

The macOS setup in this repo includes:

- A dedicated Darwin host at `hosts/darwin/default.nix`
- A dedicated Home Manager profile at `home-manager/home-darwin.nix`
- Shared shell and prompt configuration through Zsh and Starship
- nix-darwin and Home Manager integration through the flake

### Available Hosts

- **ICFGG241C3Y03**: macOS configuration using nix-darwin and Home Manager
- **krile**: Laptop configuration with KDE Plasma, development tools, and rclone mounts
- **wsl**: WSL configuration using NixOS-WSL

## Modules

### Services Module: rclone

The rclone module provides a declarative way to configure rclone mounts:

```nix
services.rclone-mounts = {
  enable = true;
  mounts.gdrive = {
    remote = "gdrive:";
    mountPoint = "/home/jhettenh/.state/remotes/gdrive";
    user = "jhettenh";
  };
};
```

### Desktop Module: plasma

Configures KDE Plasma 6 with Wayland support.

### Audio Module: pulseaudio

Configures PulseAudio with Real-Time Kit support.

### Virtualization Module: libvirt

Sets up QEMU/KVM virtualization with virt-manager.

## Home Manager Profiles

### Development Profile

Includes:

- Development tools (VS Code, Neovim, Git)
- Programming languages (Python, Node.js, Go, Rust)
- Container tools (Docker, Podman)
- Cloud tools (kubectl, Terraform, AWS CLI)

### Desktop Profile

Includes:

- Web browsers (Firefox, Chromium)
- Media applications (VLC, Spotify)
- Communication tools (Discord, Telegram)
- Productivity software (LibreOffice, Obsidian)

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
- First-time switch commands should use a path-based flake reference until all new files are tracked by Git

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
