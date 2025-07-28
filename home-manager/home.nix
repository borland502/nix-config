{ config, pkgs, ... }:

{
  home.username = "jhettenh";
  home.homeDirectory = "/home/jhettenh";
  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  xdg = {
    portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-wlr
        xdg-desktop-portal-gtk
      ];
    };
  };

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    # here is some command line tools I use frequently
    # feel free to add your own or remove some of them

    # Encryption
    age

    # GUI
    discord
    slack
    vivaldi
    keepassxc

    # archives
    zip
    xz
    unzip
    p7zip

    # virtualization
    qemu # QEMU is a generic and open source machine emulator and virtualizer
    virt-manager # Virtual Machine Manager is a desktop user interface for managing virtual machines through libvirt

    # utils
    bat
    ripgrep # recursively searches directories for a regex pattern
    fd
    jq # A lightweight and flexible command-line JSON processor
    yq-go # yaml processor https://github.com/mikefarah/yq
    eza # A modern replacement for ‘ls’
    fzf # A command-line fuzzy finder
    direnv
    rclone

    # networking tools
    mtr # A network diagnostic tool
    iperf3
    dnsutils # `dig` + `nslookup`
    ldns # replacement of `dig`, it provide the command `drill`
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    socat # replacement of openbsd-netcat
    nmap # A utility for network discovery and security auditing
    ipcalc # it is a calculator for the IPv4/v6 addresses

    # formatters
    nixfmt # A formatter for Nix code
    shfmt # A shell script formatter

    # misc
    cowsay
    file
    which
    tree
    gnused
    gnutar
    gawk
    zstd
    gnupg

    # nix related
    #
    # it provides the command `nom` works just like `nix`
    # with more details log output
    nix-output-monitor

    # productivity
    hugo # static site generator
    glow # markdown previewer in terminal
    gum

    btop # replacement of htop/nmon
    iotop # io monitoring
    iftop # network monitoring

    # system call monitoring
    strace # system call monitoring
    ltrace # library call monitoring
    lsof # list open files

    # system tools
    sysstat
    lm_sensors # for `sensors` command
    ethtool
    pciutils # lspci
    usbutils # lsusb
  ];

  programs.bat = { enable = true; };

  programs.eza = {
    enableZshIntegration = true;
    colors = "always";
    git = true;
    icons = "always";
  };

  # programs.kitty = {
  #   enable = true; # enable kitty terminal
  #   enableGitIntegration = true; # enable git integration
  #   shellIntegration.enableZshIntegration = true; # enable zsh integration
  # };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true; # enable zsh integration
  };

  programs.git = {
    enable = true;
    userName = "Jeremy Hettenhouser";
    userEmail = "jhettenh@gmail.com";
  };

  programs.plasma = import ./plasma.nix;

  programs.rclone = { enable = true; };

  # starship - an customizable prompt for any shell
  programs.starship = import ./starship.nix;

  programs.tealdeer = {
    enable = true; # enable tealdeer
    enableAutoUpdates = true; # enable auto updates
  };

  programs.zoxide = {
    enable = true; # enable zoxide
    enableZshIntegration = true; # enable zsh integration
  };

  programs.zsh = import ./zsh.nix;

  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [ yzhang.markdown-all-in-one ];
  };

  services.kdeconnect = {
    enable = true;
    indicator = true; # show the indicator in the system tray
  };

  services.unison = { enable = true; };

  # stylix = {
  #   enable = true; # enable stylix
  #   base16Scheme =
  #     ./config/colors/monokai.base24.yaml; # use monokai base24 color scheme
  #   targets = {
  #     vscode.enable = false;
  #     kitty.enable = true; # enable kitty terminal
  #     starship.enable = true; # enable starship prompt
  #   };

  #   fonts = {
  #     sansSerif = {
  #       package = pkgs.nerd-fonts.fira-code;
  #       name = "Fira Code Nerd Font";
  #     };
  #     monospace = {
  #       package = pkgs.nerd-fonts.fira-mono;
  #       name = "Fira Mono Nerd Font";
  #     };
  #   };
  # };
  # This value determines the home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update home Manager without changing this value. See
  # the home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.05";
}
