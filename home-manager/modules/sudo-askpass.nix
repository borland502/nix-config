{
  config,
  lib,
  pkgs,
  ...
}: let
  dispatcher = pkgs.writeShellScript "sudo-askpass" (builtins.readFile ../../ai-tools/scripts/sudo-askpass);
  defaultAskpass = ''
    export SUDO_ASKPASS="''${SUDO_ASKPASS:-${config.home.homeDirectory}/.local/bin/ai-tools/sudo-askpass}"
  '';
in
  lib.mkIf pkgs.stdenv.isLinux {
    home.file.".local/bin/ai-tools/sudo-askpass".source = dispatcher;
    home.sessionVariablesExtra = defaultAskpass;
    programs.zsh.envExtra = defaultAskpass;
  }
