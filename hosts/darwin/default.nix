{
  config,
  lib,
  pkgs,
  ...
}: let
  # All Homebrew activation steps, clumped and relocated to run AFTER
  # home-manager activation (see system.activationScripts.postActivation below).
  # nix-darwin's fixed activation order otherwise splits these across the run —
  # the tap-trust ran early (in extraActivation) and the bundle late — which is
  # both confusing and forces the Flameshot quarantine strip to happen before
  # the app is installed. Keeping them together, after home-manager, means a
  # VPN-blocked cask download can't abort activation before ~/.claude etc. are
  # deployed, and each step runs in dependency order.
  homebrewActivation = lib.optionalString config.homebrew.enable ''
    # --- Homebrew activation (clumped, runs after home-manager) -------------
    # 1. Homebrew 6 requires trusting third-party taps before `brew bundle` can
    #    load their formulae/casks. nix-darwin PR #1789 adds first-class
    #    support; until flake.lock includes it, trust the tap in the same
    #    --user/--set-home environment nix-darwin uses for the bundle.
    # TODO(nix-darwin-1789): drop the manual trust after flake.lock has the fix.
    if [ -x "${config.homebrew.prefix}/bin/brew" ]; then
      echo "Trusting kionsoftware/tap for Homebrew 6 activation..."
      PATH="${config.homebrew.prefix}/bin:$PATH" sudo --preserve-env=PATH --user=${lib.escapeShellArg config.homebrew.user} --set-home \
        "${config.homebrew.prefix}/bin/brew" trust --tap kionsoftware/tap || true
    fi

    # 2. Homebrew Bundle. Mirrors nix-darwin modules/homebrew.nix, reusing its
    #    own onActivation.brewBundleCmd so the actual command stays in sync.
    echo >&2 "Homebrew bundle..."
    if [ -f "${config.homebrew.prefix}/bin/brew" ]; then
      PATH="${config.homebrew.prefix}/bin:${lib.makeBinPath [pkgs.mas]}:$PATH" \
      sudo \
        --preserve-env=PATH \
        --user=${lib.escapeShellArg config.homebrew.user} \
        --set-home \
        env \
        ${config.homebrew.onActivation.brewBundleCmd}
    else
      echo -e "\e[1;31merror: Homebrew is not installed, skipping...\e[0m" >&2
    fi
  '';
in {
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

      # --- Migrated from Homebrew (2026-07-09 audit: aarch64-darwin support
      # --- now in nixpkgs). cleanup="zap" removes the brew copies on switch.
      # CLI:
      colima
      lima-additional-guestagents
      docker-credential-helpers
      ssm-session-manager-plugin
      android-tools
      # GUI apps — nix-darwin links them into /Applications/Nix Apps; TCC
      # grants re-prompt once on first launch. google-chrome + slack migrate
      # away from the root-owned casks whose upgrades kept failing.
      google-chrome
      slack
      kitty
      iterm2
      dbeaver-bin
      ice-bar
      moonlight-qt
      obsidian
      discord
      firefox
      whatsapp-for-mac
      flameshot
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

    activationScripts = {
      # Enable Touch ID for sudo authentication via activation script
      extraActivation.text = ''
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

      # Empty nix-darwin's in-place Homebrew step; all Homebrew activation now
      # runs clumped at the end of postActivation (see homebrewActivation above),
      # after home-manager has deployed ~/.claude, the Copilot instructions, and
      # run `chezmoi apply`. This keeps a VPN-blocked cask download from aborting
      # activation before the user config is written; the trailing failure is
      # tolerated at the task layer by scripts/darwin-switch-tolerant.sh.
      homebrew.text = lib.mkForce "";
      postActivation.text = lib.mkOrder 2000 homebrewActivation;
    };

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
      # Nix-packaged flameshot (migrated from the cask, which needed a
      # quarantine-strip activation step); store path needs no xattr fixups.
      ProgramArguments = ["${pkgs.flameshot}/bin/flameshot"];
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
      # TEMP: casks are bypassed from taskfile.yaml via
      # HOMEBREW_BUNDLE_CASK_SKIP while nix-darwin catches up with Homebrew 6
      # trust behavior affecting third-party taps/casks during activation.
      # TODO(nix-darwin-1789): remove the taskfile skip list after nix-darwin
      # PR #1789 lands and this repo updates flake.lock to include it.
      extraFlags = ["--force-cleanup"];
    };

    # Taps (third-party repositories)
    # NOTE: Homebrew 6.0 requires explicit tap trust (brew trust kionsoftware/tap)
    # before brew bundle will load these. nix-darwin fix pending in PR #1789.
    # Run `brew trust kionsoftware/tap` once as your user after first failure.
    taps = [
      "kionsoftware/tap"
    ];

    # CLI tools and libraries
    # Only what nixpkgs can't provide: the Kion vendor tap and nvm (node
    # versions deliberately nvm-managed — see agent-reference). colima,
    # docker-credential-helper, lima-additional-guestagents moved to
    # systemPackages (2026-07-09); pydantic dropped (no consumer found).
    brews = [
      "kion-cli"
      "aws-console"
      "nvm"
    ];

    # Casks that must stay in Homebrew (2026-07-09 audit — everything else
    # migrated to systemPackages above):
    #   vivaldi/chromium        no aarch64-darwin build in nixpkgs
    #   corretto@11             corretto11 attr isn't aarch64-darwin; swap to
    #                           temurin-bin-11 only after checking the consumer
    #   jetbrains-toolbox       self-updater fights the read-only nix store
    #   keepassxc               nixpkgs aarch64-darwin build doesn't detect the
    #                           YubiKey/hardware key even with the recommended
    #                           macOS privacy settings (2026-07-10 revert)
    # VS Code (stable) is provided by Nix via home-manager programs.vscode. The
    # Homebrew stable + insiders casks were dropped 2026-07-10: two VS Code
    # versions racing on one ~/Library/Application Support/Code profile corrupted
    # webview service workers, and nixpkgs has no insiders channel to keep synced.
    casks = [
      "corretto@11" # AWS Corretto 11 JDK for Java tooling compatibility
      "chromium" # Chromium Browser
      "jetbrains-toolbox" # JetBrains Toolbox
      "keepassxc" # Password manager — Homebrew build detects the YubiKey
      "vivaldi" # Vivaldi Browser
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
