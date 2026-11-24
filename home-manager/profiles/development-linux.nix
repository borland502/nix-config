# Development-focused home-manager profile
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (config.nixConfig.host) isWsl;
  devPackages = with pkgs;
    [
      # Build tools
      gnumake
      cmake

      # Languages and runtimes
      nodejs

      # Cloud tools
      kubectl
    ]
    ++ lib.optionals (!isWsl) [pkgs.vscode];

  availablePackages = lib.filter (pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) devPackages;
in {
  # Development tools
  home.packages = availablePackages;

  # Note: Git configuration moved to common.nix to avoid duplication
  # Note: Common dev tools (jq, yq, ripgrep, fd, bat) moved to common.nix
  # Note: VS Code profiles moved to modules/vscode-profiles.nix, which is
  # shared with darwin — this file is Linux-only and they are not.
}
