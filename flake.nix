{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    # nix-darwin for macOS system management
    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
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
      url = "github:danth/stylix/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, nix-darwin, home-manager, plasma-manager, stylix, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
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
            ({ lib, ... }: {
              home.username = "vscode";
              home.homeDirectory = "/home/vscode";
              home.activation.dconfSettings = lib.mkForce (
                lib.hm.dag.entryAfter [ "checkLinkTargets" ] ''
                  echo "Skipping dconfSettings in devcontainer (no dbus session available)."
                ''
              );
            })
          ];
        });
    in {
      # NixOS configurations
      nixosConfigurations = {
        krile = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/krile

            stylix.nixosModules.stylix

            # make home-manager as a module of nixos
            # so that home-manager configuration will be deployed automatically when executing `nixos-rebuild switch`
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = ".bak0809-1320";
              home-manager.sharedModules = [
                # Import the plasma-manager module
                plasma-manager.homeModules.plasma-manager
                stylix.homeModules.stylix
              ];

              home-manager.users.jhettenh = import ./home-manager/home.nix;

              # Optionally, use home-manager.extraSpecialArgs to pass arguments to home.nix
            }
          ];
        };
      };

      homeConfigurations = {
        "jhettenh@krile" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor "x86_64-linux";
          modules = [
            plasma-manager.homeModules.plasma-manager
            stylix.homeModules.stylix
            ./home-manager/home.nix
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

      # nix-darwin configurations for macOS
      darwinConfigurations = {
        ICFGG241C3Y03 = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            ./hosts/darwin

            stylix.darwinModules.stylix

            # Enable home-manager for nix-darwin
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = ".bak0809-1320";
              home-manager.sharedModules = [
                stylix.homeModules.stylix
              ];

              home-manager.users."42245" = import ./home-manager/home-darwin.nix;
            }
          ];
        };
      };
  };
}
