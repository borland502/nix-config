{
  pkgs,
  lib,
  ...
}: let
  linuxPackages = with pkgs; [
    iotop
    iftop
    strace
    ltrace
    sysstat
    lm_sensors
    ethtool
    pciutils
    usbutils
    dbus
    nerd-fonts.fira-code
  ];

  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  availableLinuxPackages = lib.filter availableOnHost linuxPackages;
in {
  imports = [
    ./common.nix
    ./profiles/development-linux.nix
  ];

  home = {
    username = lib.mkDefault "nixos";
    homeDirectory = lib.mkDefault "/home/nixos";

    packages = availableLinuxPackages;

    activation.dconfSettings = lib.mkForce (
      lib.hm.dag.entryAfter ["checkLinkTargets"] ''
        echo "Skipping dconfSettings in WSL (no dconf service available)."
      ''
    );

    file.".vscode-server/data/Machine/settings.json".text = builtins.toJSON {
      "terminal.integrated.defaultProfile.linux" = "zsh";
      "terminal.integrated.profiles.linux" = {
        zsh = {
          path = "${pkgs.zsh}/bin/zsh";
          args = ["-l"];
        };
      };
      "terminal.integrated.automationProfile.linux" = {
        path = "${pkgs.zsh}/bin/zsh";
        args = ["-l"];
      };
    };
  };

  stylix.targets = {
    bat.enable = lib.mkForce true;
    btop.enable = lib.mkForce true;
    fzf.enable = lib.mkForce true;
    kitty.enable = true;
    starship.enable = lib.mkForce true;
    vim.enable = lib.mkForce true;
    vscode.enable = true;
    gtk.enable = lib.mkForce false;
    kde.enable = lib.mkForce false;
  };

  programs.starship.settings = {
    format = lib.mkForce "$os$username$hostname$directory$git_branch$git_status$nix_shell$nodejs$python$rust$golang$docker_context$aws$cmd_duration$line_break$character";

    os = {
      disabled = false;
      format = "[$symbol]($style) ";
      style = "#7BD88F bold";
      symbols = {
        NixOS = " ";
        Windows = "󰍲 ";
      };
    };

    username.show_always = lib.mkForce true;

    hostname = {
      ssh_only = lib.mkForce false;
      format = lib.mkForce "[wsl@$hostname]($style) ";
      style = lib.mkForce "#fd9353 bold";
    };

    directory.truncation_length = lib.mkForce 5;
  };

  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkAfter ["DejaVu Sans"];
    serif = lib.mkAfter ["DejaVu Serif"];
  };
}
