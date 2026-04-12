{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix-darwin for macOS system management
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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
      url = "github:danth/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixos-wsl,
    nix-darwin,
    home-manager,
    plasma-manager,
    stylix,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    linuxSystems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    goGuiRuntimePackagesFor = pkgs:
      with pkgs; [
        libGL
        libxkbcommon
        wayland
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXrender
        xorg.libXfixes
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXxf86vm
      ];
    goGuiDevPackagesFor = pkgs:
      with pkgs; [
        libGL.dev
        libxkbcommon.dev
        wayland.dev
        xorg.xorgproto
        xorg.libX11.dev
        xorg.libXcursor.dev
        xorg.libXext.dev
        xorg.libXrender.dev
        xorg.libXfixes.dev
        xorg.libXi.dev
        xorg.libXinerama.dev
        xorg.libXrandr.dev
        xorg.libXxf86vm.dev
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

      stylix.darwinModules.stylix

      # Enable home-manager for nix-darwin
      home-manager.darwinModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = false;
          useUserPackages = true;
          backupFileExtension = ".bak0809-1320";
          sharedModules = [
            stylix.homeModules.stylix
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
      };
    devcontainerConfigs = nixpkgs.lib.genAttrs linuxSystems (system:
      home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor system;
        modules = [
          plasma-manager.homeModules.plasma-manager
          stylix.homeModules.stylix
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

          stylix.nixosModules.stylix

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
          home-manager.nixosModules.home-manager
          ./hosts/wsl
          {
            home-manager = {
              useGlobalPkgs = false;
              useUserPackages = true;
              backupFileExtension = ".bak0809-1320";
              sharedModules = [
                stylix.homeModules.stylix
              ];

              users.nixos = import ./home-manager/home-wsl.nix;
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
          ./home-manager/home.nix
        ];
      };

      "nixos@wsl" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor "x86_64-linux";
        modules = [
          stylix.homeModules.stylix
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

    devShells = nixpkgs.lib.genAttrs linuxSystems (system: let
      pkgs = pkgsFor system;
      goGuiPkgConfigPath = goGuiPkgConfigPathFor pkgs;
      goGuiIncludePath = goGuiIncludePathFor pkgs;
      goGuiLibraryPath = goGuiLibraryPathFor pkgs;
    in {
      go-gui = pkgs.mkShell {
        packages = with pkgs;
          [
            go
            gopls
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
    });

    # nix-darwin configurations for macOS
    darwinConfigurations = {
      darwin = mkDarwinConfig;
      ICFGG241C3Y03 = mkDarwinConfig;
    };
  };
}
