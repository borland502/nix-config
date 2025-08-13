# NixOS Configuration

Jeremy's personal NixOS configuration with modular organization and Home Manager integration.

## Structure

```text
├── flake.nix                    # Main flake configuration
├── taskfile.yaml               # Task automation for common operations
├── hosts/                      # Host-specific configurations
│   ├── common/                 # Shared configurations
│   │   ├── global.nix         # Common system settings
│   │   └── users.nix          # User configurations
│   ├── krile/                 # Krile laptop configuration
│   └── nixos/                 # Other host configuration
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
2. Update the hardware configuration for your system
3. Modify user-specific settings in `hosts/common/users.nix`

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

### Available Hosts

- **krile**: Laptop configuration with KDE Plasma, development tools, and rclone mounts
- **nixos**: Base configuration (customize as needed)

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

## Maintenance

- Run `task update && task switch` regularly to keep the system updated
- Use `task gc` to clean up old generations
- Use `task optimize` to optimize the Nix store

## Customization

To customize for your setup:

1. Update user information in `hosts/common/users.nix`
2. Modify host-specific settings in `hosts/[hostname]/`
3. Add or remove packages in the appropriate profile
4. Adjust module configurations as needed

## Migration from Old Structure

If migrating from the old monolithic configuration:

1. Backup your current configuration
2. Copy host-specific settings to the new structure
3. Test the build with `task check` and `task build`
4. Switch when ready with `task switch`
