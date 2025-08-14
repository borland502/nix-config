{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Disable nix-darwin's Nix management since we're using Determinate Nix
  nix.enable = false;

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    tree
    base16-schemes  # Required for Stylix theming
  ];

  # Ensure Homebrew is in PATH for all shells and applications
  environment.shellInit = ''
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
  '';

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;

  # Ensure Homebrew is in system PATH for all applications
  environment.variables = {
    PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:$PATH";
  };

  # Set Git commit hash for darwin-version.
  system.configurationRevision = null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Set the primary user for system defaults
  system.primaryUser = "jhettenh";

  # Enable Touch ID for sudo authentication via activation script
  system.activationScripts.extraActivation.text = ''
    echo "Setting up Touch ID for sudo..."
    if ! grep -q "pam_tid.so" /etc/pam.d/sudo; then
      # Create a backup of the original sudo pam file
      cp /etc/pam.d/sudo /etc/pam.d/sudo.backup.before.nix-darwin
      
      # Add Touch ID support to sudo
      sed -i'.bak' '2i\
auth       sufficient     pam_tid.so
' /etc/pam.d/sudo
      
      echo "Touch ID for sudo has been enabled"
    else
      echo "Touch ID for sudo is already enabled"
    fi
  '';

  # System settings
  system.defaults = {
    dock = {
      autohide = true;
      orientation = "bottom";
      tilesize = 48;
    };
    
    finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      ShowStatusBar = true;
    };
    
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      AppleKeyboardUIMode = 3;
      ApplePressAndHoldEnabled = false;
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      "com.apple.mouse.tapBehavior" = 1;
      "com.apple.sound.beep.volume" = 0.0;
    };
  };

  # Enable fonts
  fonts.packages = with pkgs; [
        # Programming fonts
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    nerd-fonts.jetbrains-mono
    nerd-fonts.sauce-code-pro
    nerd-fonts.hack
    
    # System fonts
    inter
    liberation_ttf
  ];

  # Stylix configuration for system-wide theming
  stylix = {
    enable = true;
    
    # Use your existing monokai color scheme
    base16Scheme = "${pkgs.base16-schemes}/share/themes/monokai.yaml";
    
    # Set default fonts
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      serif = {
        package = pkgs.liberation_ttf;
        name = "Liberation Serif";
      };
    };

    # Configure what gets themed
    targets = {
      # Theme console/terminal applications
      console.enable = true;
      # For macOS, we'll let home-manager handle app-specific theming
    };
  };

  # Homebrew configuration
  homebrew = {
    enable = true;
    
    # Homebrew package management
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap"; # Uninstall packages not listed in configuration
    };

    # Taps (third-party repositories)
    taps = [
      "homebrew/services"
      "oven-sh/bun"
    ];

    # CLI tools and libraries
    brews = [
      # Command-line tools not available in nixpkgs or newer versions
      "awslogs"
      "bun"
      "checkov"
      "colima"
      "dasel"
      "docker"
      "docker-buildx"
      "docker-compose"
      "direnv"
      "git"
      "go-task"
      "jq"
      "kion-cli"
      "yq"
      "mas"  # Mac App Store command line interface
      "node"
      "npm"
      "starship"
      "zsh"
    ];

    # GUI applications
    casks = [
      # GUI applications that work better via Homebrew
      "chromium"        # Chromium Browser
      "dbeaver-community" # Database management tool
      "discord"          # Discord
      "firefox"          # Firefox Browser
      "google-chrome"    # Google Chrome
      "iterm2"           # iTerm2 terminal
      "keepassxc"
      "kitty"            # Kitty terminal
      "obsidian"         # Note-taking app
      "rectangle"        # Window management
      "raycast"          # Spotlight replacement
      "session-manager-plugin"
      "slack"            # Team communication
      "visual-studio-code" # VS Code
      "vivaldi"          # Vivaldi Browser
    ];

    # Mac App Store applications
    masApps = {
      # Mac App Store applications (find IDs with: mas search "app name")
      "Xcode" = 497799835;
    };
  };
}
