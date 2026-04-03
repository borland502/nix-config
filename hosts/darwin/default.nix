{pkgs, ...}: {
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Disable nix-darwin's Nix management since we're using Determinate Nix
  nix.enable = false;

  environment = {
    # List packages installed in system profile
    systemPackages = with pkgs; [
      vim
      git
      curl
      wget
      htop
      tree
      base16-schemes # Required for Stylix theming
    ];

    # Ensure Homebrew is in PATH for all shells and applications
    shellInit = ''
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:$PATH"
    '';

    # Ensure Homebrew is in system PATH for all applications
    variables = {
      PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:$PATH";
    };
  };

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;

  system = {
    # Set Git commit hash for darwin-version.
    configurationRevision = null;

    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    stateVersion = 5;

    # Set the primary user for system defaults
    primaryUser = "42245";

    # Enable Touch ID for sudo authentication via activation script
    activationScripts.extraActivation.text = ''
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

    # Strip quarantine from Flameshot after Homebrew installs it to bypass Gatekeeper.
    # nix-darwin activation now runs as root, so a regular activation script is sufficient.
    activationScripts.flameshotQuarantineFix.text = ''
      if [ -d "/Applications/Flameshot.app" ]; then
        echo "Stripping quarantine attribute from Flameshot..."
        xattr -cr /Applications/Flameshot.app || true
      fi
    '';

    # System settings
    defaults = {
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
        # Disable macOS default capture shortcuts so Flameshot can claim the
        # native chords it supports on macOS. Flameshot exposes global actions
        # for Cmd+Shift+4 and Cmd+Shift+3; the clipboard variants remain
        # disabled because Flameshot does not provide native macOS global
        # bindings for them.
        "com.apple.symbolichotkeys" = {
          AppleSymbolicHotKeys = {
            # Cmd + Shift + 4 (Rectangular capture)
            "30" = {enabled = false;};
            # Cmd + Ctrl + Shift + 4 (Rectangular capture to clipboard)
            "31" = {enabled = false;};
            # Cmd + Shift + 3 (Full screen capture)
            "28" = {enabled = false;};
            # Cmd + Ctrl + Shift + 3 (Full screen capture to clipboard)
            "29" = {enabled = false;};
          };
        };

        "com.apple.Spotlight" = let
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

          mkItem = enabled: name: {inherit name enabled;};
        in {
          orderedItems =
            (map (mkItem 1) enableCategories)
            ++ (map (mkItem 0) disableCategories);
        };
      };
    };
  };

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  launchd.user.agents.flameshot = {
    serviceConfig = {
      KeepAlive = true;
      ProgramArguments = ["/Applications/Flameshot.app/Contents/MacOS/flameshot"];
      ProcessType = "Interactive";
      RunAtLoad = true;
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

  # Homebrew configuration for macOS-only GUI apps and vendor-specific formulae.
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
      "kionsoftware/tap"
      "atlassian/homebrew-acli"
    ];

    # CLI tools and libraries
    brews = [
      "acli"
      "aws-console"
      "colima"
      "docker-credential-helper"
      "kion-cli"
      "lima-additional-guestagents"
      "nvm"
      "pydantic"
    ];

    # GUI applications
    casks = [
      # GUI applications that work better via Homebrew
      "android-platform-tools"
      "chromium" # Chromium Browser
      "dbeaver-community" # Database management tool
      "discord" # Discord
      "firefox" # Firefox Browser
      "flameshot" # Flameshot screenshot tool
      "google-chrome" # Google Chrome
      "iterm2" # iTerm2 terminal
      "jetbrains-toolbox" # JetBrains Toolbox
      "jordanbaird-ice"
      "keepassxc"
      "kitty" # Kitty terminal
      "obsidian" # Note-taking app
      "moonlight"
      "postman"
      "postman-cli"
      "session-manager-plugin"
      "slack" # Team communication
      "visual-studio-code" # VS Code
      "vivaldi" # Vivaldi Browser
      "whatsapp"
    ];

    # Mac App Store applications
    masApps = {
      # Mac App Store applications (find IDs with: mas search "app name")
      "Xcode" = 497799835;
      # Kindle upgrades are currently failing via `mas` with MASError 5 on this host.
      # Keep it out of automated brew bundle runs so Darwin upgrades stay reliable.
      "Unzip - RAR ZIP 7Z Unarchiver" = 1537056818;
    };
  };
}
