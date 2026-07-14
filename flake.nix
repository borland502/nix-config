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
    # Tracks fast-moving upstream releases (currently used only for the
    # claude-code / github-copilot-cli overlay below — nixos-26.05 lags
    # Anthropic/GitHub Copilot CLI releases by days-to-weeks).
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
    #   - fast-moving CLI agents (claude-code, github-copilot-cli)
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
      # fast-moving CLI agents
      inherit (unstable) claude-code github-copilot-cli;
      # Electron apps (see comment above)
      inherit (unstable) vscode slack discord obsidian;
      # Browsers under Nix control (see comment above). vivaldi is only used on
      # Linux; the inherit stays lazy on darwin where nothing references it.
      inherit (unstable) google-chrome firefox vivaldi;
    };
    nixpkgsOverlayModule = {nixpkgs.overlays = [unstableOverlay];};
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
    darwinModules = [
      ./hosts/darwin
      nixpkgsOverlayModule

      stylix.darwinModules.stylix
      sops-nix.darwinModules.default

      # Enable home-manager for nix-darwin
      home-manager.darwinModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = false;
          useUserPackages = true;
          backupFileExtension = ".bak0809-1320";
          sharedModules = [
            stylix.homeModules.stylix
            sops-nix.homeManagerModules.sops
          ];

          users."42245" = import ./home-manager/home-darwin.nix;
        };
      }
    ];
    mkDarwinConfig = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = darwinModules;
    };
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
        overlays = [unstableOverlay];
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
    devcontainerConfigs = nixpkgs.lib.genAttrs linuxSystems (system:
      home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor system;
        modules = [
          plasma-manager.homeModules.plasma-manager
          stylix.homeModules.stylix
          sops-nix.homeManagerModules.sops
          ./home-manager/home.nix
          ({lib, ...}: {
            home = {
              username = "vscode";
              homeDirectory = "/home/vscode";
              activation.dconfSettings = lib.mkForce (
                lib.hm.dag.entryAfter ["checkLinkTargets"] ''
                  echo "Skipping dconfSettings in devcontainer (no dbus session available)."
                ''
              );
            };
          })
        ];
      });
  in {
    # NixOS configurations
    nixosConfigurations = {
      linux = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/linux
          nixpkgsOverlayModule

          stylix.nixosModules.stylix
          sops-nix.nixosModules.sops

          # make home-manager as a module of nixos
          # so that home-manager configuration will be deployed automatically when executing `nixos-rebuild switch`
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = false;
              useUserPackages = true;
              backupFileExtension = ".bak0809-1320";
              sharedModules = [
                # Import the plasma-manager module
                plasma-manager.homeModules.plasma-manager
                stylix.homeModules.stylix
                sops-nix.homeManagerModules.sops
              ];

              users.jhettenh = import ./home-manager/home.nix;

              # Optionally, use home-manager.extraSpecialArgs to pass arguments to home.nix
            };
          }
        ];
      };

      wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixos-wsl.nixosModules.default
          nixpkgsOverlayModule
          home-manager.nixosModules.home-manager
          sops-nix.nixosModules.sops
          ./hosts/wsl
          {
            home-manager = {
              useGlobalPkgs = false;
              useUserPackages = true;
              backupFileExtension = ".bak0809-1320";
              sharedModules = [
                stylix.homeModules.stylix
                sops-nix.homeManagerModules.sops
              ];

              users.jhettenh = import ./home-manager/home-wsl.nix;
            };
          }
        ];
      };
    };

    homeConfigurations = {
      "jhettenh@linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor "x86_64-linux";
        modules = [
          plasma-manager.homeModules.plasma-manager
          stylix.homeModules.stylix
          sops-nix.homeManagerModules.sops
          ./home-manager/home.nix
        ];
      };

      "jhettenh@nixos-wsl" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor "x86_64-linux";
        modules = [
          stylix.homeModules.stylix
          sops-nix.homeManagerModules.sops
          ./home-manager/home-wsl.nix
        ];
      };

      "jhettenh@debian-wsl" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor "x86_64-linux";
        modules = [
          stylix.homeModules.stylix
          sops-nix.homeManagerModules.sops
          ./home-manager/home-wsl.nix
        ];
      };

      "jhettenh@ubuntu-wsl" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor "x86_64-linux";
        modules = [
          stylix.homeModules.stylix
          sops-nix.homeManagerModules.sops
          ./home-manager/home-wsl.nix
        ];
      };

      "vscode@devcontainer" = devcontainerConfigs."x86_64-linux";
      "vscode@devcontainer-aarch64" = devcontainerConfigs."aarch64-linux";
    };

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
      }
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

    # nix-darwin configurations for macOS
    darwinConfigurations = {
      darwin = mkDarwinConfig;
      ICFGG241C3Y03 = mkDarwinConfig;
    };
  };
}
