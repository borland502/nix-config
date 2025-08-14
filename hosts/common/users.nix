# Common user configuration
{ config, lib, pkgs, ... }:

{
  # User account configuration
  users.users.jhettenh = {
    isNormalUser = true;
    description = "Jeremy Hettenhouser";
    extraGroups = [ "networkmanager" "wheel" "fuse" ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      kdePackages.kate
      firefox
      thunderbird
    ];
  };

  # Note: Font configuration moved to home-manager common.nix
  # This avoids duplication between system and user-level configs
}
