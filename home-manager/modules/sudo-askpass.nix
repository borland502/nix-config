{
  config,
  lib,
  pkgs,
  ...
}: let
  helpers = [
    "/usr/bin/ksshaskpass"
    "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass"
    "/usr/bin/ssh-askpass"
    "/usr/libexec/openssh/gnome-ssh-askpass"
    "/usr/bin/lxqt-openssh-askpass"
    "/usr/lib/ssh/x11-ssh-askpass"
  ];
  dispatcher = pkgs.writeShellScript "sudo-askpass" (
    builtins.replaceStrings ["@ASKPASS_HELPERS@"] [(lib.escapeShellArgs helpers)]
    (builtins.readFile ../../ai-tools/scripts/sudo-askpass)
  );
  defaultAskpass = ''
    export SUDO_ASKPASS="''${SUDO_ASKPASS:-${config.home.homeDirectory}/.local/bin/ai-tools/sudo-askpass}"
  '';
in
  lib.mkIf pkgs.stdenv.isLinux {
    home.file.".local/bin/ai-tools/sudo-askpass".source = dispatcher;
    home.sessionVariablesExtra = defaultAskpass;
    programs.zsh.envExtra = defaultAskpass;
  }
