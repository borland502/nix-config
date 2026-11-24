{
  description = "NixOS configuration";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # Tracks fast-moving upstream releases for the overlay below (Electron
    # apps + Nix-managed browsers, which nixos-26.05 lags on for
    # Chromium/security fixes). The agent CLIs (claude-code, github-copilot-cli)
    # are deliberately NOT here — they install off nixpkgs via
    # ~/.local/bin/update-agent-clis, each using its vendor's native
    # self-updating installer into ~/.local. Even nixpkgs-unstable lags the
    # GitHub Copilot CLI by weeks, and a read-only nix-store copy cannot
    # self-update, so it stays frozen on a build whose hardcoded subagent model
    # allowlist rejects current models (e.g. gpt-5.6 luna). See
    # docs/agent-token-cost-levers.md.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix-darwin for macOS system management
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    stylix = {
      url = "github:danth/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixpkgs-unstable,
    nixos-wsl,
    nix-darwin,
    home-manager,
    plasma-manager,
    stylix,
    sops-nix,
    ...
  }: let
    # Packages tracked on nixos-unstable while the rest of the repo stays on
    # nixos-26.05. See AGENTS.md / docs notes if expanded.
    #   - Electron apps: they ship frequent Chromium/security fixes and the
    #     stable channel lags badly. Keeping them current also stops their
    #     bundled Chromium from drifting against any other copy that shares an
    #     app profile — mismatched Electron builds on one
    #     ~/Library/Application Support profile corrupt webview service workers
    #     (2026-07-10: a Homebrew VS Code 1.128 and Nix VS Code 1.119 sharing
    #     the Code profile broke the Claude panel webview this way).
    #   - Browsers: same reasoning — frequent Chromium/security fixes the
    #     stable channel lags on. (Only the Nix-managed browsers; darwin's
    #     Vivaldi/Chromium remain Homebrew casks.)
    unstableOverlay = _final: prev: let
      unstable = import nixpkgs-unstable {
        system = prev.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      };
    in {
      # Electron apps (see comment above)
      inherit (unstable) vscode slack discord obsidian;
      # Browsers under Nix control (see comment above). vivaldi is only used on
      # Linux; the inherit stays lazy on darwin where nothing references it.
      inherit (unstable) google-chrome firefox;
      # vivaldi needs proprietaryCodecs=true so it ships a working libffmpeg.so
      # (symlinked from vivaldi-ffmpeg-codecs). Without it, the bundled free
      # codec triggers Vivaldi's "fix this for the next restart" auto-download,
      # which then fails to load and crashes vivaldi on launch with
      # "libffmpeg.so: cannot open shared object file" — so apps handing off a
      # URL (e.g. Slack sign-in via the KDE OpenURI portal) open nothing.
      vivaldi = unstable.vivaldi.override {proprietaryCodecs = true;};
    };
    # Tools built from this repo (see pkgs/). Exposed through an overlay so any
    # home-manager or NixOS module can list them in `packages` like any other
    # package, without threading `self` through extraSpecialArgs.
    localPackagesOverlay = final: _prev: import ./pkgs final;
    nixpkgsOverlayModule = {nixpkgs.overlays = [unstableOverlay localPackagesOverlay];};
    # home-manager runs with useGlobalPkgs = false, so it instantiates its own
    # nixpkgs and does NOT inherit `nixpkgs.overlays` from the system module.
    # Anything home.packages references by bare name has to come through this
    # module instead, added to every sharedModules list below. Without it the
    # NixOS configs fail to evaluate with "undefined variable 'gopwgen'".
    hmOverlayModule = {nixpkgs.overlays = [unstableOverlay localPackagesOverlay];};
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    linuxSystems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    goGuiRuntimePackagesFor = pkgs:
      with pkgs; [
        libGL
        libxkbcommon
        wayland
        libx11
        libxcursor
        libxext
        libxrender
        libxfixes
        libxi
        libxinerama
        libxrandr
        libxxf86vm
      ];
    goGuiDevPackagesFor = pkgs:
      with pkgs; [
        libGL.dev
        libxkbcommon.dev
        wayland.dev
        xorgproto
        libx11.dev
        libxcursor.dev
        libxext.dev
        libxrender.dev
        libxfixes.dev
        libxi.dev
        libxinerama.dev
        libxrandr.dev
        libxxf86vm.dev
      ];
    goGuiPkgConfigPathFor = pkgs: let
      goGuiDevPackages = goGuiDevPackagesFor pkgs;
    in
      (nixpkgs.lib.makeSearchPath "lib/pkgconfig" goGuiDevPackages)
      + ":"
      + (nixpkgs.lib.makeSearchPath "share/pkgconfig" goGuiDevPackages);
    goGuiIncludePathFor = pkgs: nixpkgs.lib.makeSearchPath "include" (goGuiDevPackagesFor pkgs);
    goGuiLibraryPathFor = pkgs: nixpkgs.lib.makeLibraryPath (goGuiRuntimePackagesFor pkgs);
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
        overlays = [unstableOverlay localPackagesOverlay];
      };
    repoDevShellFor = pkgs:
      pkgs.mkShell {
        packages = with pkgs; [
          alejandra
          deadnix
          fd
          git
          go-task
          jq
          nixd
          ripgrep
          statix
        ];
      };
    hostConfigurations = import ./nix/host-configurations.nix {
      root = ./.;
      inherit
        nixpkgs
        nix-darwin
        home-manager
        plasma-manager
        stylix
        sops-nix
        nixos-wsl
        nixpkgsOverlayModule
        hmOverlayModule
        pkgsFor
        ;
    };
  in {
    inherit (hostConfigurations) nixosConfigurations homeConfigurations darwinConfigurations;

    # Tools built from this repo — see pkgs/default.nix for the registry.
    packages = forAllSystems (system: import ./pkgs (pkgsFor system));

    # Build every registered package, including tools not installed by Home Manager.
    checks = forAllSystems (system: import ./pkgs (pkgsFor system));

    apps = forAllSystems (system: {
      home-manager = {
        type = "app";
        program = "${home-manager.packages.${system}.home-manager}/bin/home-manager";
        meta = {
          description = "Home Manager CLI helper";
        };
      };
    });

    devShells = nixpkgs.lib.genAttrs systems (system: let
      pkgs = pkgsFor system;
    in
      {
        default = repoDevShellFor pkgs;
        validation = import ./nix/validation-shell.nix {inherit pkgs;};
      }
      // (import ./nix/package-dev-shells.nix {inherit pkgs;})
      // (
        if builtins.elem system linuxSystems
        then let
          goGuiPkgConfigPath = goGuiPkgConfigPathFor pkgs;
          goGuiIncludePath = goGuiIncludePathFor pkgs;
          goGuiLibraryPath = goGuiLibraryPathFor pkgs;
        in {
          go-gui = pkgs.mkShell {
            packages = with pkgs;
              [
                go
                gopls
                govulncheck
                delve
                pkg-config
                gcc
              ]
              ++ (goGuiRuntimePackagesFor pkgs)
              ++ (goGuiDevPackagesFor pkgs);

            shellHook = ''
              export PKG_CONFIG_PATH="${goGuiPkgConfigPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
              export CPATH="${goGuiIncludePath}''${CPATH:+:$CPATH}"
              export LIBRARY_PATH="${goGuiLibraryPath}''${LIBRARY_PATH:+:$LIBRARY_PATH}"
              export LD_LIBRARY_PATH="${goGuiLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              export GDK_BACKEND="wayland,x11"
              export QT_QPA_PLATFORM="wayland;xcb"
              export SDL_VIDEODRIVER="wayland,x11"
              export MOZ_ENABLE_WAYLAND=1
              export NIXOS_OZONE_WL=1
            '';
          };
        }
        else {}
      ));
  };
}
