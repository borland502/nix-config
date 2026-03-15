# NixOS WSL host configuration
{ pkgs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "nixos";

  networking.hostName = "wsl";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  users.users.nixos.shell = pkgs.zsh;

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    zsh
  ];

  system.stateVersion = "25.11";
}
