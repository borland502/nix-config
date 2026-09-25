{
  config,
  pkgs,
  lib,
  ...
}: let
  agentInstructions = import ./lib/agent-instructions.nix {inherit pkgs;};
  # Flameshot (Qt6 QSettings) rewrites this INI at runtime, so it cannot be a
  # read-only nix-store symlink; it is seeded as a mutable copy in
  # home.activation.seedFlameshotConfig below.
  flameshotIni = pkgs.writeText "flameshot.ini" ''
    [General]
    contrastOpacity=188
    saveAfterCopy=true
    startupLaunch=true
    useJpgForClipboard=true

    [Shortcuts]
    SCREENSHOT_HISTORY=Ctrl+Shift+3
    TAKE_SCREENSHOT=Ctrl+Shift+4
  '';
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
  # mermaid-cli drives headless Chrome through puppeteer, but nixpkgs only wires
  # PUPPETEER_EXECUTABLE_PATH into the mmdc wrapper when chromium is available
  # on the host platform — and chromium has no darwin build. The stock package
  # therefore installs fine here and then fails at render time with puppeteer's
  # "Could not find Chrome" (the vendored download is disabled at build time via
  # PUPPETEER_SKIP_DOWNLOAD). Point it at the same nix-provided Chrome that
  # hosts/darwin/default.nix installs, so mmdc does not depend on whichever
  # browser happens to be in /Applications.
  mermaidCli = pkgs.symlinkJoin {
    name = "mermaid-cli-with-chrome";
    paths = [pkgs.mermaid-cli];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/mmdc \
        --set PUPPETEER_EXECUTABLE_PATH ${lib.escapeShellArg (lib.getExe pkgs.google-chrome)}
    '';
  };
  keychainCaBundle = "${config.xdg.dataHome}/ca-certificates/keychain-bundle.pem";
  codexHome = "${config.xdg.configHome}/codex";
  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  darwinPackages = lib.filter availableOnHost (with pkgs; [
    mas
    vivaldiBrowserWrapper
    zoom-us # Zoom has a clean Nix path on darwin, so no Homebrew cask needed
    kitty # default terminal; stylix themes it and kitty.conf is managed here
    mermaidCli # mmdc — mermaid diagram renderer (Chrome-wrapped above)

    # `java`/`javac` on PATH for the Mac's Java work, and the JDK the shared
    # maven from common.nix runs on. Darwin-only for now: the Linux and WSL
    # hosts do no Java work, and maven's wrapper finds its own JDK there.
    # SDKMAN used to supply this and was dropped 2026-09-08. On darwin pkgs.jdk
    # is Azul's Zulu 21 — the same store path modules/vscode-profiles.nix pins
    # jdt.ls to, so the editor and the shell cannot disagree about versions.
    jdk
  ]);
in {
  _module.args.isWsl = lib.mkDefault false;

  # False: macOS ships python 3.9 and has been winding its bundled python down
  # for years, so nixpkgs' is both newer and the one worth having on $PATH.
  _module.args.preferSystemPython = lib.mkDefault false;

  imports = [
    ./common.nix # Import common configuration
    ./modules/gdrive-sync.nix # daily launchd agent for sync-to-gdrive
    ./modules/keepass-snapshot.nix # weekly dated snapshots of the vault on Drive
    ./modules/vscode-profiles.nix # language profiles, shared with Linux
    # Homebrew is reserved for macOS-only GUI apps and formulae without a clean Nix path.
  ];

  home = {
    username = "42245";
    homeDirectory = lib.mkForce "/Users/42245";

    # Darwin-specific packages
    packages = darwinPackages;
    sessionVariables = {
      BROWSER = "vivaldi";
      # Nix's OpenSSL curl otherwise follows SSL_CERT_DIR and misses certificates
      # available through macOS's system CA bundle.
      SSL_CERT_FILE = "/etc/ssl/cert.pem";
      # The Codex CLI (update-agent-clis) verifies TLS with rustls against
      # SSL_CERT_FILE, which lacks the MDM-deployed roots that a TLS-inspecting
      # proxy re-signs chatgpt.com with — every backend call then fails and the
      # TUI dies with "workspace routing discovery failed". Point it at
      # /etc/ssl/cert.pem plus the admin-trusted keychain roots, built by
      # home.activation.buildKeychainCaBundle below. Only Codex, not
      # SSL_CERT_FILE globally: a missing bundle then breaks one tool, not all.
      CODEX_CA_CERTIFICATE = keychainCaBundle;
    };

    # ~/gdrive is the Drive root on every host, so one path —
    # ~/gdrive/keepass/secrets.kdbx — resolves everywhere: the KeePass vault is
    # opened in place there by both hosts and the phone, never copied. On Linux
    # that path is an rclone FUSE mount (modules/rclone-mounts.nix); here it is
    # a symlink into the Drive Desktop client's mount, which is precisely what
    # makes macFUSE unnecessary — rclone mount on darwin needs a kernel
    # extension behind a reboot and a security prompt, which is why
    # rclone-mounts.nix is Linux-only.
    #
    # mkOutOfStoreSymlink, not a plain `source`: the target must stay a live
    # path. A plain source would copy the whole of Drive into /nix/store.
    file."gdrive".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/Library/CloudStorage/GoogleDrive-jhettenh@gmail.com/My Drive";

    activation = {
      # Remove stale *.instructions.md files from macOS skill/agent bridge
      # prompt directories left behind by older generations before the bridge
      # generators switched to *.prompt.md.
      cleanupStaleInstructionBridgesDarwin = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        for _dir in \
          "$HOME/Library/Application Support/Code/User/prompts/skills" \
          "$HOME/Library/Application Support/Code/User/prompts/agents"; do
          [ -d "$_dir" ] || continue
          for _f in "$_dir"/*.instructions.md; do
            [ -f "$_f" ] && [ ! -L "$_f" ] || continue
            ${pkgs.coreutils}/bin/rm -f "$_f"
          done
        done
      '';

      # Flameshot rewrites its own INI at runtime (Qt QSettings atomic
      # temp-file + rename), which clobbers a read-only xdg.configFile symlink
      # and has been observed to blank the file, wiping the custom capture
      # shortcuts. Seed a mutable, flameshot-owned copy instead, reseeding only
      # when the [Shortcuts] block is missing (fresh install or after such a
      # blanking) so flameshot's own [General] edits survive otherwise.
      seedFlameshotConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        flameshot_ini="$HOME/.config/flameshot/flameshot.ini"
        if [ ! -s "$flameshot_ini" ] || ! ${pkgs.gnugrep}/bin/grep -q '^\[Shortcuts\]' "$flameshot_ini"; then
          echo "Seeding Flameshot config with custom capture shortcuts"
          ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$flameshot_ini")"
          ${pkgs.coreutils}/bin/cp ${flameshotIni} "$flameshot_ini"
          ${pkgs.coreutils}/bin/chmod u+w "$flameshot_ini"
          # Flameshot only reads the INI at startup; reload the running launchd
          # agent so the restored shortcuts take effect without a manual restart.
          /bin/launchctl kickstart -k "gui/$(${pkgs.coreutils}/bin/id -u)/org.nixos.flameshot" >/dev/null 2>&1 || true
        fi
      '';

      # Rebuilt every switch so MDM root rotations are picked up. Only certs in
      # the admin trust-settings domain are appended (the MDM-deployed roots);
      # the System keychain also holds device-identity leaf certs that must not
      # become trust anchors.
      buildKeychainCaBundle = lib.hm.dag.entryAfter ["writeBoundary"] ''
        _bundle=${lib.escapeShellArg keychainCaBundle}
        _work=$(${pkgs.coreutils}/bin/mktemp -d)
        ${pkgs.coreutils}/bin/cat /etc/ssl/cert.pem > "$_work/bundle.pem"
        if /usr/bin/security trust-settings-export -d "$_work/admin.plist" >/dev/null 2>&1; then
          /usr/bin/plutil -convert xml1 -o - "$_work/admin.plist" \
            | ${pkgs.gnugrep}/bin/grep -oE '<key>[0-9A-F]{40}</key>' \
            | ${pkgs.gnused}/bin/sed -E 's#</?key>##g' > "$_work/sha1"
          /usr/bin/security find-certificate -a -Z -p /Library/Keychains/System.keychain \
            | ${pkgs.gawk}/bin/awk -v list="$_work/sha1" '
                BEGIN { while ((getline l < list) > 0) want[l] = 1 }
                /^SHA-256 hash:/ { next }
                /^SHA-1 hash:/ { keep = ($3 in want); next }
                keep { print }
              ' >> "$_work/bundle.pem"
        fi
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$_bundle")"
        # A running Codex daemon captured its env (and so its CA set) at
        # spawn; restarting it here could kill in-flight work, so say so.
        if ! ${pkgs.diffutils}/bin/cmp -s "$_work/bundle.pem" "$_bundle" \
          && /usr/bin/pgrep -qf 'codex app-server --listen .* --managed-daemon'; then
          echo "buildKeychainCaBundle: CA bundle changed; run 'codex app-server daemon restart' from a new shell" >&2
        fi
        ${pkgs.coreutils}/bin/mv "$_work/bundle.pem" "$_bundle"
        ${pkgs.coreutils}/bin/rm -rf "$_work"
      '';

      # CODEX_HOME (zsh.nix) is $XDG_CONFIG_HOME/codex, but the ChatGPT desktop
      # app bundles its own codex app-server that reads ~/.codex and never sees
      # shell env — so ~/.codex stays as a symlink to the XDG dir and the CLI
      # and the app keep sharing one login, config, and session store. Moving
      # the live SQLite stores under a running app or daemon would corrupt
      # them, so an existing ~/.codex is migrated only when nothing is using
      # it; otherwise this warns and retries on the next switch. Runs before
      # checkLinkTargets so the move lands before home-manager links the
      # xdg.configFile."codex/*" files. If a deferred run already let those
      # links populate $_codex_home, the move merges into it: zsh.nix holds
      # CODEX_HOME back until ~/.codex is a symlink, so the XDG dir can only
      # hold home-manager links, which win (--update=none) over stale copies.
      linkCodexHome = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        _codex_home=${lib.escapeShellArg codexHome}
        _legacy="$HOME/.codex"
        if [ -L "$_legacy" ]; then
          :
        elif [ -d "$_legacy" ]; then
          if /usr/bin/pgrep -qf '/ChatGPT\.app/|/\.codex/packages/.*/codex app-server'; then
            echo "linkCodexHome: ChatGPT.app or a codex app-server is running; quit it (codex app-server daemon stop) and rerun the switch to move ~/.codex" >&2
          elif [ -e "$_codex_home" ]; then
            ${pkgs.coreutils}/bin/cp -a --update=none "$_legacy/." "$_codex_home/" \
              && ${pkgs.coreutils}/bin/rm -rf "$_legacy" \
              && ${pkgs.coreutils}/bin/ln -s "$_codex_home" "$_legacy"
          else
            ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$_codex_home")"
            ${pkgs.coreutils}/bin/mv "$_legacy" "$_codex_home"
            ${pkgs.coreutils}/bin/ln -s "$_codex_home" "$_legacy"
          fi
        else
          ${pkgs.coreutils}/bin/mkdir -p "$_codex_home"
          ${pkgs.coreutils}/bin/ln -sfn "$_codex_home" "$_legacy"
        fi
      '';

      # SDKMAN! was removed on 2026-09-08. It installed itself by curling
      # get.sdkman.io outside the store, and its shell init prepended
      # ~/.sdkman/candidates to PATH — which shadowed the Nix-managed maven
      # from common.nix and made JAVA_HOME point at a JDK 11 that no longer
      # meets redhat.java's minimum of 21. The single JDK is now pkgs.jdk
      # (Zulu 21 on darwin), referenced by path from modules/vscode-profiles.nix;
      # Nix's maven wrapper finds it with no JAVA_HOME set. Projects that must
      # emit Java 11 bytecode do it with `--release 11` in their own build
      # files, which needs no JDK 11 on the machine.

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

      # LaunchServices keeps a registration for every bundle it has ever seen,
      # and duplicates that claim one bundle id break handler binding. Two
      # sources of duplicates recur on this host:
      #
      #   * Homebrew cask upgrades rename the outgoing bundle aside as
      #     /Applications/<App>.app.broken-<version> rather than deleting it.
      #     The leftover keeps claiming the original bundle id, and
      #     LSSetDefaultHandlerForURLScheme then fails with -54 on the ambiguous
      #     id. That is how the 2026-07-20 Vivaldi cask upgrade (8.0.4033.44 ->
      #     8.1.4087.55) silently reverted http/https to Safari: this activation
      #     step ran, failed with -54, and only warned.
      #   * Every nix rebuild of a GUI app mints a new /nix/store path; the
      #     superseded generations stay registered until their store path is
      #     garbage-collected.
      #
      # Pruning only drops LaunchServices entries — it never touches files.
      pruneStaleAppRegistrations = lib.hm.dag.entryBefore ["setDefaultBrowser"] ''
        lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
        if [ -x "$lsregister" ]; then
          # Cask upgrade leftovers: a complete, superseded bundle under its
          # original id. Always safe to unregister; the file stays on disk.
          for stale in /Applications/*.app.broken-*; do
            [ -e "$stale" ] || continue
            echo "Unregistering stale cask leftover: $stale"
            "$lsregister" -u "$stale" >/dev/null 2>&1 || true
          done

          # Store-path registrations, pruned under two narrow rules:
          #
          #   1. The store path no longer exists (dead generation after a GC).
          #   2. The app also exists in ~/Applications/Home Manager Apps. That
          #      copy is the canonical, Spotlight-indexable bundle; the store
          #      duplicate is always redundant. This matters because Spotlight
          #      cannot index /nix, so whenever LaunchServices resolves a bundle
          #      id to a store path the app disappears from Cmd-Space. The
          #      `code` CLI execs the store path directly and re-registers it on
          #      every launch, so this needs re-running, not a one-off cleanup.
          #
          # Superseded generations that are still on disk and have no Home
          # Manager Apps counterpart are left alone: unregistering those is a
          # no-op once the app relaunches, and risks dropping the only
          # registration an app has.
          hm_apps="$HOME/Applications/Home Manager Apps"
          "$lsregister" -dump 2>/dev/null \
            | ${pkgs.gnused}/bin/sed -n 's|^[[:space:]]*path:[[:space:]]*\(/nix/store/.*\.app\)[[:space:]]*(0x[0-9a-f]*)[[:space:]]*$|\1|p' \
            | sort -u \
            | while IFS= read -r bundle; do
                if [ ! -e "$bundle" ]; then
                  echo "Unregistering dead store registration: $bundle"
                elif [ -e "$hm_apps/''${bundle##*/}" ]; then
                  echo "Unregistering store duplicate of ''${bundle##*/}: $bundle"
                else
                  continue
                fi
                "$lsregister" -u "$bundle" >/dev/null 2>&1 || true
              done

          # A store-launched app that has since quit can leave the canonical
          # copy unregistered; re-assert it so Spotlight keeps the app.
          if [ -d "$hm_apps" ]; then
            for app in "$hm_apps"/*.app; do
              [ -e "$app" ] || continue
              "$lsregister" -f "$app" >/dev/null 2>&1 || true
            done
          fi
        fi
      '';

      setDefaultBrowser = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if [ -d "/Applications/Vivaldi.app" ]; then
          if ! ${setDefaultBrowser}/bin/set-default-browser com.vivaldi.Vivaldi; then
            # Loud on purpose: this previously failed with -54 and the warning
            # scrolled past in an otherwise-successful switch, leaving Safari as
            # the default browser for hours.
            echo "ERROR: failed to register Vivaldi as the default browser." >&2
            echo "       Usually an ambiguous com.vivaldi.Vivaldi bundle id (LaunchServices -54)." >&2
            echo "       Check for duplicates:  lsregister -dump | grep -i 'Vivaldi\.app'" >&2
            echo "       Then re-run:           set-default-browser com.vivaldi.Vivaldi" >&2
          fi
        else
          echo "Skipping Vivaldi default browser registration: /Applications/Vivaldi.app is unavailable."
        fi
      '';
    };

    # Install shared editor settings and Copilot defaults into the macOS
    # user configuration directory for the (stable) VS Code app.
    file = {
      "Library/Application Support/Code/User/prompts/copilot-defaults.instructions.md".source = agentInstructions.copilot;
      "Library/Application Support/Code/User/prompts/skills" = {
        source = agentInstructions.copilotSkillBridgeDir;
        recursive = true;
      };
      "Library/Application Support/Code/User/prompts/agents" = {
        source = agentInstructions.copilotAgentBridgeDir;
        recursive = true;
      };

      # VS Code stable settings are deployed via programs.vscode.userSettings in
      # common.nix (home-manager's vscode module writes the same settings.json).
      # chat.hookFilesLocations is currently only honoured by Copilot >= 0.53;
      # once stable ships that version the hooks will start working there too
      # automatically — no code change needed.
      # TODO(mainline-vscode): remove this comment once stable ships Copilot >= 0.53.
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

      # No SDKMAN init here on purpose — see the note by installNvmNode above.
      # Leaving it sourced would keep ~/.sdkman/candidates ahead of the Nix
      # profile on PATH even after the installer is gone.

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

  # VS Code is not configured here. common.nix enables it and owns the shared
  # userSettings; modules/vscode-profiles.nix (imported above) owns the profile
  # layout and is shared with Linux, so the two hosts cannot drift. Adding a
  # local `programs.vscode` block here is what let darwin fall behind before.
  # Kitty terminal configuration
  # Codex (macOS-only, update-agent-clis) gets the same ai-tools content as
  # Claude (plugin) and Copilot (copilot/skills + copilot/agents in common.nix),
  # under CODEX_HOME. Codex reads $CODEX_HOME/AGENTS.md as global
  # instructions, scans $CODEX_HOME/skills (it keeps its own skills/.system
  # beside these, so the dir is linked file-by-file), and loads
  # $CODEX_HOME/agents/*.toml as custom subagents.
  # CODEX_CA_CERTIFICATE (sessionVariables) only reaches processes started from
  # a login shell, but Codex's long-lived app-server daemon keeps the env of
  # whichever process first spawned it, and ChatGPT.app's bundled codex
  # app-server is launched from the Dock. Either one missing the var is the
  # "workspace routing discovery failed" TUI error again. Publish it into the
  # launchd user domain at login so every GUI app (and terminals opened from
  # them) inherits it. /bin/launchctl, not a nix-store binary: launchd agents
  # that exec through the nix profile get killed for code-signing (LWCR).
  launchd.agents.codex-ca-env = {
    enable = true;
    config = {
      ProgramArguments = ["/bin/launchctl" "setenv" "CODEX_CA_CERTIFICATE" keychainCaBundle];
      RunAtLoad = true;
    };
  };

  xdg.configFile = {
    "codex/AGENTS.md".source = agentInstructions.codex;
    "codex/skills" = {
      source = ../ai-tools/skills;
      recursive = true;
    };
    "codex/agents" = {
      source = agentInstructions.codexAgentDir;
      recursive = true;
    };
    # Bash command logging, as for Claude and Copilot: Codex's PostToolUse
    # payload is Claude-shaped (tool_name "Bash", tool_input.command,
    # tool_response as the model-facing output string), so log-bash.sh's Claude
    # branch handles it. Codex skips non-managed hooks until they are trusted
    # once in /hooks; trust is keyed to this definition's hash.
    "codex/hooks.json".text = builtins.toJSON {
      hooks.PostToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = ''AGENT_NAME=codex exec bash "$HOME/.local/bin/ai-tools/log-bash.sh"'';
            }
          ];
        }
      ];
    };
  };

  xdg.configFile."kitty/kitty.conf".text = let
    c = import ./lib/colors.nix;
    baseCfg = builtins.readFile ../chezmoi/dot_config/kitty/kitty.conf;
  in
    baseCfg
    + ''

      # Theme: Monokai Spectrumish
      # Source: chezmoi/dot_config/colors/monokai.toml
      foreground ${c.base05}
      background ${c.base00}
      cursor     ${c.base05}

      color0  ${c.base00}
      color8  ${c.base03}
      color1  ${c.base08}
      color9  ${c.base12}
      color2  ${c.base0B}
      color10 ${c.base14}
      color3  ${c.base0A}
      color11 ${c.base13}
      color4  ${c.base0D}
      color12 ${c.base16}
      color5  ${c.base0E}
      color13 ${c.base0E}
      color6  ${c.base0C}
      color14 ${c.base15}
      color7  ${c.base05}
      color15 ${c.base07}
    '';
}
