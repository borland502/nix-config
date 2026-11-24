{
  root,
  nixpkgs,
  nix-darwin,
  home-manager,
  plasma-manager,
  stylix,
  sops-nix,
  nixos-wsl,
  nixpkgsOverlayModule,
  hmOverlayModule,
  pkgsFor,
}: let
  commonHomeModules = [stylix.homeModules.stylix sops-nix.homeManagerModules.sops];
  linuxHomeModules = [plasma-manager.homeModules.plasma-manager] ++ commonHomeModules;
  integratedHome = {
    user,
    home,
    gui ? false,
  }: {
    home-manager = {
      useGlobalPkgs = false;
      useUserPackages = true;
      backupFileExtension = ".bak0809-1320";
      sharedModules =
        [hmOverlayModule]
        ++ (
          if gui
          then linuxHomeModules
          else commonHomeModules
        );
      users.${user} = home;
    };
  };
  standalone = {
    system ? "x86_64-linux",
    home,
    gui ? false,
    extraModules ? [],
  }:
    home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor system;
      modules =
        (
          if gui
          then linuxHomeModules
          else commonHomeModules
        )
        ++ [home] ++ extraModules;
    };
  wslHome = standalone {home = root + /home-manager/home-wsl.nix;};
  devcontainer = system:
    standalone {
      inherit system;
      home = root + /home-manager/home.nix;
      gui = true;
      extraModules = [
        ({lib, ...}: {
          home = {
            username = "vscode";
            homeDirectory = "/home/vscode";
            activation.dconfSettings = lib.mkForce (lib.hm.dag.entryAfter ["checkLinkTargets"] ''
              echo "Skipping dconfSettings in devcontainer (no dbus session available)."
            '');
          };
        })
      ];
    };
  darwin = nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      (root + /hosts/darwin)
      nixpkgsOverlayModule
      stylix.darwinModules.stylix
      sops-nix.darwinModules.default
      home-manager.darwinModules.home-manager
      (integratedHome {
        user = "42245";
        home = import (root + /home-manager/home-darwin.nix);
      })
    ];
  };
in {
  nixosConfigurations = {
    linux = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        (root + /hosts/linux)
        nixpkgsOverlayModule
        stylix.nixosModules.stylix
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        (integratedHome {
          user = "jhettenh";
          gui = true;
          home = {
            imports = [(root + /home-manager/home.nix)];
            nixConfig.host = {
              isNixos = true;
              preferSystemPython = false;
            };
          };
        })
      ];
    };
    wsl = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        nixpkgsOverlayModule
        home-manager.nixosModules.home-manager
        sops-nix.nixosModules.sops
        (root + /hosts/wsl)
        (integratedHome {
          user = "jhettenh";
          home = import (root + /home-manager/home-wsl.nix);
        })
      ];
    };
  };
  homeConfigurations = {
    "jhettenh@linux" = standalone {
      gui = true;
      home = root + /home-manager/home.nix;
    };
    "jhettenh@tifa" = standalone {
      gui = true;
      home = root + /home-manager/home-tifa.nix;
    };
    "jhettenh@nixos-wsl" = wslHome;
    "jhettenh@debian-wsl" = wslHome;
    "jhettenh@ubuntu-wsl" = wslHome;
    "vscode@devcontainer" = devcontainer "x86_64-linux";
    "vscode@devcontainer-aarch64" = devcontainer "aarch64-linux";
  };
  darwinConfigurations = {
    inherit darwin;
    ICFGG241C3Y03 = darwin;
  };
}
