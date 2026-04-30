{
  pkgs,
  lib,
  ...
}: let
  codeEditorUserSettings = import ./lib/code-editor-user-settings.nix {inherit pkgs;};
  agentInstructions = import ./lib/agent-instructions.nix {inherit pkgs;};
  vivaldiBrowserWrapper = pkgs.writeShellScriptBin "vivaldi" ''
    exec /usr/bin/open -a "Vivaldi" "$@"
  '';
  setDefaultBrowserSource = pkgs.writeText "set-default-browser.c" ''
    #include <CoreFoundation/CoreFoundation.h>
    #include <CoreServices/CoreServices.h>
    #include <stdbool.h>
    #include <stdio.h>
    #include <stdlib.h>

    static bool cfstring_equals_case_insensitive(CFStringRef left, CFStringRef right) {
      return left != NULL && right != NULL && CFStringCompare(left, right, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
    }

    static bool default_handler_for_url_scheme_matches(const char *scheme, CFStringRef bundle_identifier) {
      CFStringRef scheme_ref = CFStringCreateWithCString(kCFAllocatorDefault, scheme, kCFStringEncodingUTF8);
      if (scheme_ref == NULL) {
        return false;
      }

      CFStringRef current_handler = LSCopyDefaultHandlerForURLScheme(scheme_ref);
      CFRelease(scheme_ref);

      bool matches = cfstring_equals_case_insensitive(current_handler, bundle_identifier);
      if (current_handler != NULL) {
        CFRelease(current_handler);
      }

      return matches;
    }

    static bool default_handler_for_content_type_matches(const char *content_type, LSRolesMask role, CFStringRef bundle_identifier) {
      CFStringRef content_type_ref = CFStringCreateWithCString(kCFAllocatorDefault, content_type, kCFStringEncodingUTF8);
      if (content_type_ref == NULL) {
        return false;
      }

      CFStringRef current_handler = LSCopyDefaultRoleHandlerForContentType(content_type_ref, role);
      CFRelease(content_type_ref);

      bool matches = cfstring_equals_case_insensitive(current_handler, bundle_identifier);
      if (current_handler != NULL) {
        CFRelease(current_handler);
      }

      return matches;
    }

    static bool set_default_handler_for_url_scheme(const char *scheme, CFStringRef bundle_identifier) {
      if (default_handler_for_url_scheme_matches(scheme, bundle_identifier)) {
        return true;
      }

      CFStringRef scheme_ref = CFStringCreateWithCString(kCFAllocatorDefault, scheme, kCFStringEncodingUTF8);
      if (scheme_ref == NULL) {
        fprintf(stderr, "set-default-browser: could not create CFString for URL scheme '%s'\n", scheme);
        return false;
      }

      OSStatus status = LSSetDefaultHandlerForURLScheme(scheme_ref, bundle_identifier);
      CFRelease(scheme_ref);
      if (status != noErr) {
        fprintf(stderr, "set-default-browser: failed to set handler for URL scheme '%s' (error %d)\n", scheme, (int)status);
        return false;
      }

      return true;
    }

    static bool set_default_handler_for_content_type(const char *content_type, LSRolesMask role, CFStringRef bundle_identifier) {
      if (default_handler_for_content_type_matches(content_type, role, bundle_identifier)) {
        return true;
      }

      CFStringRef content_type_ref = CFStringCreateWithCString(kCFAllocatorDefault, content_type, kCFStringEncodingUTF8);
      if (content_type_ref == NULL) {
        fprintf(stderr, "set-default-browser: could not create CFString for content type '%s'\n", content_type);
        return false;
      }

      OSStatus status = LSSetDefaultRoleHandlerForContentType(content_type_ref, role, bundle_identifier);
      CFRelease(content_type_ref);
      if (status != noErr) {
        fprintf(stderr, "set-default-browser: failed to set handler for content type '%s' (error %d)\n", content_type, (int)status);
        return false;
      }

      return true;
    }

    int main(int argc, char *argv[]) {
      if (argc != 2) {
        fprintf(stderr, "usage: %s <bundle-identifier>\n", argv[0]);
        return 64;
      }

      CFStringRef bundle_identifier = CFStringCreateWithCString(kCFAllocatorDefault, argv[1], kCFStringEncodingUTF8);
      if (bundle_identifier == NULL) {
        fprintf(stderr, "set-default-browser: could not create CFString for bundle identifier '%s'\n", argv[1]);
        return 1;
      }

      bool success = true;
      success = set_default_handler_for_url_scheme("http", bundle_identifier) && success;
      success = set_default_handler_for_url_scheme("https", bundle_identifier) && success;
      success = set_default_handler_for_content_type("public.xhtml", kLSRolesAll, bundle_identifier) && success;

      CFRelease(bundle_identifier);
      return success ? 0 : 1;
    }
  '';
  setDefaultBrowser = pkgs.runCommandCC "set-default-browser" {} ''
    mkdir -p "$out/bin"
    "$CC" -Wall -Wextra -O2 -o "$out/bin/set-default-browser" ${setDefaultBrowserSource} -framework CoreServices -framework CoreFoundation
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

      setDefaultBrowser = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if [ -d "/Applications/Vivaldi.app" ]; then
          if ! ${setDefaultBrowser}/bin/set-default-browser com.vivaldi.Vivaldi; then
            echo "Warning: failed to register Vivaldi as the default browser; leaving existing LaunchServices handlers unchanged"
          fi
        else
          echo "Skipping Vivaldi default browser registration: /Applications/Vivaldi.app is unavailable."
        fi
      '';

      installClaudeExtension = lib.hm.dag.entryAfter ["writeBoundary"] ''
        stable_code="/opt/homebrew/bin/code"
        insiders_code="/opt/homebrew/bin/code-insiders"
        claude_ext="anthropic.claude-code"

        if [ -x "$stable_code" ]; then
          if ! "$stable_code" --list-extensions 2>/dev/null | grep -qi "^''${claude_ext}$"; then
            echo "Installing Claude Code extension in VS Code stable"
            "$stable_code" --install-extension "$claude_ext" >/dev/null 2>&1 \
              || echo "Warning: failed to install ''${claude_ext} in VS Code stable"
          fi
        else
          echo "Skipping Claude Code extension install for VS Code stable: code not found at $stable_code"
        fi

        if [ -x "$insiders_code" ]; then
          if ! "$insiders_code" --list-extensions 2>/dev/null | grep -qi "^''${claude_ext}$"; then
            echo "Installing Claude Code extension in VS Code Insiders"
            "$insiders_code" --install-extension "$claude_ext" >/dev/null 2>&1 \
              || echo "Warning: failed to install ''${claude_ext} in VS Code Insiders"
          fi
        else
          echo "Skipping Claude Code extension install for VS Code Insiders: code-insiders not found at $insiders_code"
        fi
      '';

      syncCodeInsidersExtensions = lib.hm.dag.entryAfter ["writeBoundary"] ''
        stable_code="/opt/homebrew/bin/code"
        insiders_code="/opt/homebrew/bin/code-insiders"

        if [ ! -x "$stable_code" ] || [ ! -x "$insiders_code" ]; then
          echo "Skipping VS Code Insiders extension sync: code or code-insiders is unavailable."
        else
          mkdir -p "$HOME/.vscode-insiders/extensions"
          tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"
          cleanup() {
            ${pkgs.coreutils}/bin/rm -rf "$tmp_dir"
          }
          trap cleanup EXIT INT TERM

          "$stable_code" --list-extensions | ${pkgs.coreutils}/bin/sort -u > "$tmp_dir/stable-extensions.txt"
          "$insiders_code" --list-extensions | ${pkgs.coreutils}/bin/sort -u > "$tmp_dir/insiders-extensions.txt"

          ${pkgs.coreutils}/bin/comm -23 "$tmp_dir/stable-extensions.txt" "$tmp_dir/insiders-extensions.txt" | while IFS= read -r extension; do
            if [ -z "$extension" ]; then
              continue
            fi

            echo "Installing VS Code Insiders extension: $extension"
            if ! "$insiders_code" --install-extension "$extension" >/dev/null 2>&1; then
              extension_store_path="$(${pkgs.findutils}/bin/find /nix/store -path "*/share/vscode/extensions/$extension" 2>/dev/null | ${pkgs.coreutils}/bin/head -n 1)"
              if [ -n "$extension_store_path" ]; then
                extension_version="$(${pkgs.jq}/bin/jq -r '.version // "nix"' "$extension_store_path/package.json" 2>/dev/null)"
                ${pkgs.coreutils}/bin/ln -sfn "$extension_store_path" "$HOME/.vscode-insiders/extensions/$extension-$extension_version"
                echo "Linked Nix-managed VS Code Insiders extension: $extension"
              else
                echo "Warning: failed to install VS Code Insiders extension '$extension'"
              fi
            fi
          done

          cleanup
          trap - EXIT INT TERM
        fi
      '';
    };

    # Install shared editor settings and Copilot defaults into the macOS
    # user configuration directories for the stable and Insiders VS Code apps.
    file = {
      "Library/Application Support/Code/User/prompts/copilot-defaults.instructions.md".source = agentInstructions.copilot;
      "Library/Application Support/Code - Insiders/User/prompts/copilot-defaults.instructions.md".source = agentInstructions.copilot;
      "Library/Application Support/Code - Insiders/User/settings.json".text = builtins.toJSON codeEditorUserSettings;
    };
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
  xdg.configFile."flameshot/flameshot.ini".source = ./config/flameshot/flameshot.ini;
  # Kitty terminal configuration
  xdg.configFile."kitty/kitty.conf".source = ./config/kitty/kitty.conf;
}
