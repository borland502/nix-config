# Development-focused home-manager profile
{ config, pkgs, lib, ... }:

let
  devPackages = with pkgs; [
    # Editors and IDEs
    vscode
    neovim

    # Build tools
    gnumake
    cmake

    # Languages and runtimes
    nodejs
    python3
    go

    # Containers and virtualization
    docker
    docker-compose

    # Cloud tools
    kubectl
    awscli2
  ];

  availablePackages = lib.filter (pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) devPackages;
in
{
  # Development tools
  home.packages = availablePackages;

  # Note: Git configuration moved to common.nix to avoid duplication
  # Note: Common dev tools (jq, yq, ripgrep, fd, bat) moved to common.nix

  # VS Code configuration
  programs.vscode = lib.mkIf (pkgs ? vscode) {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      # Python development
      ms-python.python

      # Git integration
      eamodio.gitlens

      # Themes and appearance
      pkief.material-icon-theme

      # Web development
      bradlc.vscode-tailwindcss
      esbenp.prettier-vscode
      ritwickdey.liveserver
    ];
  };
}
