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
      # GNU coreutils ahead of the BSD userland so shell scripts (cache-scan,
      # log-bash.sh, etc.) can rely on GNU flags like `stat -c`. Linux/WSL have
      # GNU coreutils natively; this makes darwin match.
      coreutils
    ];

    # Ensure Homebrew is in PATH for all shells and applications
    shellInit = ''
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:$PATH"
    '';

    # Ensure Homebrew is in system PATH for all applications
    variables = {
      PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:$PATH";
    };

    # Let `task switch` skip a cask in `brew bundle` via HOMEBREW_BUNDLE_CASK_SKIP.
    # nix-darwin runs the bundle under `sudo --preserve-env=PATH`, which strips
    # every other env var, so without this env_keep the taskfile-set value never
    # reaches brew. Used to skip the Discord upgrade on networks that DPI-block
    # the Discord CDN; the taskfile only sets the var when the cask is already
    # installed, so a missing cask is still installed normally. (sudo's
    # #includedir ignores filenames containing a dot, so keep this dotless.)
    etc."sudoers.d/20-homebrew-bundle-skip" = {
      text = ''
        Defaults env_keep += "HOMEBREW_BUNDLE_CASK_SKIP"
      '';
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
      # Homebrew 4.7+ refuses `brew bundle install --cleanup` without an
      # explicit force flag; nix-darwin doesn't add one, so pass it here.
      extraFlags = ["--force-cleanup"];
    };

    # Taps (third-party repositories)
    taps = [
      "kionsoftware/tap"
    ];

    # CLI tools and libraries
    brews = [
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
      "corretto@11" # AWS Corretto 11 JDK for Java tooling compatibility
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
      "visual-studio-code@insiders" # VS Code Insiders
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
