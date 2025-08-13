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

  # Common fonts configuration
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    nerd-fonts.symbols-only
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "Fira Code Nerd Font Mono" ];
      sansSerif = [ "Fira Sans Nerd Font" ];
      serif = [ "Fira Serif Nerd Font" ];
    };
  };
}
