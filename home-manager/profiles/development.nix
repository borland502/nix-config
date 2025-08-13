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
    yq-go
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
    rustc
    cargo
    
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
    profiles.default.extensions = with pkgs.vscode-extensions; [
      # Python development
      ms-python.python
      
      # Rust development  
      rust-lang.rust-analyzer
      
      # Git integration
      eamodio.gitlens
      
      # Themes and appearance
      dracula-theme.theme-dracula
      pkief.material-icon-theme
      
      # Web development
      bradlc.vscode-tailwindcss
      esbenp.prettier-vscode
      ms-vscode.live-server
    ];
  };
}
