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
  ];

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;

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
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
  ];
}
