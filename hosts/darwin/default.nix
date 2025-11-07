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
  system.primaryUser = "42245";

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
      show-recents = false;
      tilesize = 48;
    };

    finder = {
      AppleShowAllExtensions = true;
      FXDefaultSearchScope = "SCcf"; # Search current folder by default
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv"; # List view
      ShowPathbar = true;
      ShowStatusBar = true;
    };

    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      ApplePressAndHoldEnabled = false;
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      NSDocumentSaveNewDocumentsToCloud = false;
      "com.apple.mouse.tapBehavior" = 1;
      "com.apple.sound.beep.volume" = 0.0;
      "com.apple.swipescrolldirection" = false;
    };

    screencapture = {
      location = "$HOME/Pictures/Screenshots";
      target = "clipboard";
      type = "png";
    };

    CustomUserPreferences = {
      "com.apple.Spotlight" =
        let
          enableCategories = [
            "APPLICATIONS"
            "SYSTEM_PREFS"
            "DIRECTORIES"
            "PDF"
            "FONTS"
            "DOCUMENTS"
            "MESSAGES"
            "CONTACT"
            "EVENT_TODO"
            "IMAGES"
            "BOOKMARKS"
            "MUSIC"
            "MOVIES"
            "PRESENTATIONS"
            "SPREADSHEETS"
            "SOURCE"
            "MENU_DEFINITION"
            "MENU_OTHER"
            "MENU_CONVERSION"
            "MENU_EXPRESSION"
          ];

          disableCategories = [
            "MENU_WEBSEARCH"
            "MENU_SPOTLIGHT_SUGGESTIONS"
          ];

          mkItem = enabled: name: { inherit name enabled; };
        in {
          orderedItems =
            (map (mkItem 1) enableCategories)
            ++ (map (mkItem 0) disableCategories);
        };
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

  # Note: Stylix system configuration disabled to avoid conflicts
  # Theming is handled at the home-manager level

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
      "oven-sh/bun"
      "kionsoftware/tap"
    ];

    # CLI tools and libraries
    brews = [
      # Command-line tools not available in nixpkgs or newer versions
      "awscli"
      "aws-console"
      "awslogs"
      "aws-sam-cli"
      "bun"
      "checkov"
      "colima"
      "dasel"
      "docker"
      "docker-buildx"
      "docker-compose"
      "docker-credential-helper"
      "direnv"
      "git"
      "golang"
      "go-task"
      "jq"
      "kion-cli"
      "lima-additional-guestagents"
      "mas"  # Mac App Store command line interface
      "maven"
      "nvm"
      "overmind"
      "python@3"
      "scrcpy"
      "starship"
      "tmux"
      "unzip"
      "yq"
      "zsh"
    ];

    # GUI applications
    casks = [
      # GUI applications that work better via Homebrew
      "android-platform-tools"
      "chromium"        # Chromium Browser
      "dbeaver-community" # Database management tool
      "discord"          # Discord
      "firefox"          # Firefox Browser
      "google-chrome"    # Google Chrome
      "iterm2"           # iTerm2 terminal
      "jetbrains-toolbox" # JetBrains Toolbox
      "jordanbaird-ice"
      "keepassxc"
      "kitty"            # Kitty terminal
      "obsidian"         # Note-taking app
      "session-manager-plugin"
      "slack"            # Team communication
      "visual-studio-code" # VS Code
      "vivaldi"          # Vivaldi Browser
      "whatsapp"
    ];

    # Mac App Store applications
    masApps = {
      # Mac App Store applications (find IDs with: mas search "app name")
      "Xcode" = 497799835;
      "Amazon Kindle" = 302584613;
      "Unzip - RAR ZIP 7Z Unarchiver" = 1537056818;
    };
  };
}
