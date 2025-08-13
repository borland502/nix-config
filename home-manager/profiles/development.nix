# Development-focused home-manager profile
{ config, pkgs, ... }:

{
  # Development tools
  home.packages = with pkgs; [
    # Editors and IDEs
    vscode
    neovim
    
    # Version control
    git
    gh
    
    # Development utilities
    jq
    yq
    ripgrep
    fd
    bat
    
    # Build tools
    gnumake
    cmake
    
    # Languages and runtimes
    nodejs
    python3
    go
    rust
    
    # Containers and virtualization
    docker
    docker-compose
    podman
    
    # Cloud tools
    kubectl
    terraform
    awscli2
  ];

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Jeremy Hettenhouser";
    userEmail = "jeremy@example.com"; # Update with your email
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  # VS Code configuration
  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      # Language support
      ms-python.python
      rust-lang.rust-analyzer
      bradlc.vscode-tailwindcss
      
      # Git integration
      eamodio.gitlens
      
      # Theme and UI
      dracula-theme.theme-dracula
      pkief.material-icon-theme
      
      # Utilities
      ms-vscode.live-server
      esbenp.prettier-vscode
    ];
  };
}
