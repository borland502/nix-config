_: let
  starshipSettings = import ./lib/starship-settings.nix;
in {
  programs.starship = {
    enable = true;
    enableZshIntegration = false;
    settings = starshipSettings;
  };
}
