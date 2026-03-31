{
  pkgs,
  lib,
  ...
}: let
  vivaldiBrowserWrapper = pkgs.writeShellScriptBin "vivaldi" ''
    exec /usr/bin/open -a "Vivaldi" "$@"
  '';
  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  darwinPackages = lib.filter availableOnHost (with pkgs; [
    mas
    vivaldiBrowserWrapper
  ]);
in {
  _module.args.isWsl = lib.mkDefault false;

  imports = [
    ./common.nix # Import common configuration
    # Homebrew is reserved for macOS-only GUI apps and formulae without a clean Nix path.
  ];

  home = {
    username = "42245";
    homeDirectory = lib.mkForce "/Users/42245";

    # Darwin-specific packages
    packages = darwinPackages;
    sessionVariables.BROWSER = "vivaldi";

    activation = {
      # Install SDKMAN! on macOS so Java toolchains can be managed declaratively
      installSdkman = lib.hm.dag.entryAfter ["writeBoundary"] ''
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

      # Keep Node.js off Homebrew on macOS; install the latest release through nvm instead.
      installNvmNode = lib.hm.dag.entryAfter ["writeBoundary"] ''
        install_env_path="${pkgs.curl}/bin:${pkgs.wget}/bin:${pkgs.coreutils}/bin:${pkgs.gawk}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        export PATH="$install_env_path"
        export TERM=dumb
        export NVM_DIR="$HOME/.nvm"
        mkdir -p "$NVM_DIR"

        if [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
          set +u
          . "/opt/homebrew/opt/nvm/nvm.sh"
          export NVM_SYMLINK_CURRENT=true
          nvm install node >/dev/null
          nvm alias default node >/dev/null
          nvm use default >/dev/null
          set -u
        else
          echo "Homebrew nvm is not installed; skipping Node.js installation"
        fi
      '';

      installConfluenceCli = lib.hm.dag.entryAfter ["installNvmNode"] ''
        install_env_path="${pkgs.curl}/bin:${pkgs.wget}/bin:${pkgs.coreutils}/bin:${pkgs.gawk}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.jq}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        export PATH="$install_env_path"
        export TERM=dumb
        export NVM_DIR="$HOME/.nvm"

        if [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
          set +u
          . "/opt/homebrew/opt/nvm/nvm.sh"
          export NVM_SYMLINK_CURRENT=true
          if nvm use default >/dev/null 2>&1; then
            current_version="$(${pkgs.coreutils}/bin/timeout 30s bash -lc 'npm list -g confluence-cli --depth=0 --json 2>/dev/null || true' | ${pkgs.jq}/bin/jq -r '.dependencies["confluence-cli"].version // empty' 2>/dev/null || true)"
            latest_version="$(${pkgs.coreutils}/bin/timeout 30s npm view confluence-cli version 2>/dev/null || true)"

            if [ -z "$latest_version" ]; then
              echo "Unable to resolve latest confluence-cli version; leaving current install unchanged"
            elif [ "$current_version" != "$latest_version" ]; then
              echo "Installing confluence-cli $latest_version via npm"
              if ! npm install -g "confluence-cli@$latest_version" >/dev/null 2>&1; then
                echo "npm install for confluence-cli failed; leaving current install unchanged"
              fi
            else
              echo "confluence-cli $current_version already installed"
            fi
          else
            echo "nvm default Node is unavailable; skipping confluence-cli installation"
          fi
          set -u
        else
          echo "Homebrew nvm is not installed; skipping confluence-cli installation"
        fi
      '';

      setDefaultBrowser = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if [ -d "/Applications/Vivaldi.app" ]; then
          ${pkgs.duti}/bin/duti -s com.vivaldi.Vivaldi http all
          ${pkgs.duti}/bin/duti -s com.vivaldi.Vivaldi https all
          ${pkgs.duti}/bin/duti -s com.vivaldi.Vivaldi public.xhtml all
        else
          echo "Skipping Vivaldi default browser registration: /Applications/Vivaldi.app is unavailable."
        fi
      '';
    };

    # Install the shared Copilot defaults into the macOS VS Code user prompts directory.
    file."Library/Application Support/Code/User/prompts/copilot-defaults.instructions.md".source = ./config/copilot/copilot-defaults.instructions.md;
  };

  # Darwin-specific Stylix targets (extending common.nix)
  stylix.targets = {
    # Keep Firefox Stylix integration off on macOS for now; Firefox itself is installed via Homebrew.
    firefox.enable = false;
    kitty.enable = true;
    vscode.enable = true;
  };

  # Darwin-specific font fallbacks
  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkAfter ["Helvetica" "Arial"];
    serif = lib.mkAfter ["Times New Roman" "Times"];
  };

  # Darwin-specific shell configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    initContent = ''
      # Ensure Homebrew is in PATH (critical for GUI terminals like kitty)
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

      # Make sure locally installed CLI tools (pipx, npm, etc.) are reachable
      export PATH="$HOME/.local/bin:$PATH"

      # Disable loading of old zsh configurations that might conflict
      # This prevents zmodule errors from old Zim framework
      unset ZIM_HOME
      unset ZIM_CONFIG_FILE

      export SDKMAN_DIR="$HOME/.sdkman"
      if [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
        source "$SDKMAN_DIR/bin/sdkman-init.sh"
      fi

      export NVM_DIR="$HOME/.nvm"
      if [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
        source "/opt/homebrew/opt/nvm/nvm.sh"
      fi
      if [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ]; then
        source "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
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

  # VSCode configuration with Stylix theming
  programs.vscode = {
    enable = true;
    # Extensions and other VSCode config can be added here
    # Stylix will automatically handle theming
  };
  # Kitty terminal configuration
  xdg.configFile."kitty/kitty.conf".source = ./config/kitty/kitty.conf;
}
