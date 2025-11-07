{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix           # Import common configuration
    # Homebrew casks and packages are used for dev and desktop specific tasks
  ];

  home.username = "42245";
  home.homeDirectory = lib.mkForce "/Users/42245";

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
    firefox = {
      enable = true;
      profileNames = [ "default" ];
    };
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

      export SDKMAN_DIR="$HOME/.sdkman"
      if [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
        source "$SDKMAN_DIR/bin/sdkman-init.sh"
      fi

      export NVM_DIR="$HOME/.nvm"
      if [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh"
      fi
      if [ -s "$NVM_DIR/bash_completion" ]; then
        source "$NVM_DIR/bash_completion"
      fi
      export NVM_SYMLINK_CURRENT=true
      if command -v nvm >/dev/null 2>&1; then
        nvm use --install default >/dev/null 2>&1 || true
      fi
      current_node_modules="$NVM_DIR/versions/node/current/lib/node_modules"
      if [ -d "$current_node_modules" ]; then
        export NODE_PATH="$current_node_modules''${NODE_PATH:+:$NODE_PATH}"
      fi
      current_node_bin="$NVM_DIR/versions/node/current/bin"
      if [ -d "$current_node_bin" ]; then
        export PATH="$current_node_bin:$PATH"
      fi
    '';
  };

  # Install SDKMAN! on macOS so Java toolchains can be managed declaratively
  home.activation.installSdkman = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    sdkman_dir="$HOME/.sdkman"
    if [ ! -s "$sdkman_dir/bin/sdkman-init.sh" ]; then
      echo "Installing SDKMAN! into $sdkman_dir"
      tmp_home="$(${pkgs.coreutils}/bin/mktemp -d)"
      cleanup() {
        ${pkgs.coreutils}/bin/rm -rf "$tmp_home"
      }
      trap cleanup EXIT INT TERM
      install_env_path="${pkgs.unzip}/bin:${pkgs.zip}/bin:${pkgs.gnutar}/bin:${pkgs.curl}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gawk}/bin:$PATH"
      env PATH="$install_env_path" HOME="$tmp_home" ZDOTDIR="$tmp_home" SDKMAN_DIR="$sdkman_dir" \
        ${pkgs.curl}/bin/curl -sSf "https://get.sdkman.io?rcupdate=false" -o "$tmp_home/install-sdkman.sh"
      env PATH="$install_env_path" HOME="$tmp_home" ZDOTDIR="$tmp_home" SDKMAN_DIR="$sdkman_dir" \
        ${pkgs.bash}/bin/bash "$tmp_home/install-sdkman.sh"
      cleanup
      trap - EXIT INT TERM
    else
      echo "SDKMAN! already present"
    fi
  '';

  # VSCode configuration with Stylix theming
  programs.vscode = {
    enable = true;
    # Extensions and other VSCode config can be added here
    # Stylix will automatically handle theming
  };

  # Kitty terminal configuration
  xdg.configFile."kitty/kitty.conf".source = ./config/kitty/kitty.conf;
}
