# NixOS WSL host configuration
{pkgs, ...}: {
  wsl = {
    enable = true;
    defaultUser = "nixos";
    docker-desktop.enable = true;
    interop.register = true;
    useWindowsDriver = true;
    startMenuLaunchers = true;
  };

  programs.nix-ld.enable = true;

  networking.hostName = "wsl";

  nix.settings.experimental-features = ["nix-command" "flakes"];

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
