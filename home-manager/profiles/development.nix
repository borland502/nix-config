# Development-focused home-manager profile
{ config, pkgs, ... }:

{
  # Development tools
  home.packages = with pkgs; [
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
    podman
    
    # Cloud tools
    kubectl
    awscli2
  ];

  # Note: Git configuration moved to common.nix to avoid duplication
  # Note: Common dev tools (jq, yq, ripgrep, fd, bat) moved to common.nix

  # VS Code configuration
  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
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
