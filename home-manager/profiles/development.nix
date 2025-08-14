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
    go-task
    
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

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Jeremy Hettenhouser";
    userEmail = "jhettenh@gmail.com";
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
           
      # Git integration
      eamodio.gitlens
      
      # Themes and appearance
      pkief.material-icon-theme
      
      # Web development
      bradlc.vscode-tailwindcss
      esbenp.prettier-vscode
      ms-vscode.live-server
    ];
  };
}
