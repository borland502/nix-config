{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix           # Import common configuration
    # Note: development profile disabled to avoid VSCode unfree issue
  ];

  home.username = "jhettenh";
  home.homeDirectory = lib.mkForce "/Users/jhettenh";

  # Darwin-specific packages
  home.packages = with pkgs; [
    # macOS-specific GUI applications
    firefox
    # Note: Many GUI apps on macOS are better installed via Homebrew or App Store
  ];

  # Darwin-specific Stylix targets (extending common.nix)
  stylix.targets = {
    kitty.enable = true;
    vscode.enable = true;
  };

  # Darwin-specific font fallbacks
  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkAfter [ "Helvetica" "Arial" ];
    serif = lib.mkAfter [ "Times New Roman" "Times" ];
  };

  # Darwin-specific shell configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    initContent = ''
      # Ensure home-manager packages are in PATH
      export PATH="$HOME/.local/state/nix/profiles/home-manager/home-path/bin:$PATH"
      
      # Ensure Homebrew is in PATH (critical for GUI terminals like kitty)
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
      
      # Disable loading of old zsh configurations that might conflict
      # This prevents zmodule errors from old Zim framework
      unset ZIM_HOME
      unset ZIM_CONFIG_FILE
    '';
  };

  # VSCode configuration with Stylix theming
  programs.vscode = {
    enable = true;
    # Extensions and other VSCode config can be added here
    # Stylix will automatically handle theming
  };

  # Kitty terminal configuration
  xdg.configFile."kitty/kitty.conf".source = ./config/kitty/kitty.conf;
}
