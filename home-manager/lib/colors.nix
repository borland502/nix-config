# Nix mirror of home-manager/config/colors/monokai.base24.yaml.
# Keep both files in sync when changing the colour scheme.
# Used by starship-settings.nix, zsh.nix, home-wsl.nix, and home-darwin.nix.
let
  palette = {
    # Backgrounds
    base00 = "#222222"; # Default background
    base01 = "#363537"; # Lighter background (status bars, line numbers)
    base02 = "#525053"; # Selection background
    base03 = "#69676c"; # Comments, invisibles
    # Foregrounds
    base04 = "#8b888f"; # Dark foreground (status bars)
    base05 = "#bab6c0"; # Default foreground
    base06 = "#fbf8ff"; # Light foreground
    base07 = "#f7f1ff"; # Light background
    # Syntax colours
    base08 = "#FC618D"; # Variables, markup link text — pink/red
    base09 = "#fd9353"; # Integers, constants — orange
    base0A = "#FCE566"; # Classes, search highlight — yellow
    base0B = "#7BD88F"; # Strings, markup code — green
    base0C = "#5AD4E6"; # Support, escape chars — cyan
    base0D = "#948ae3"; # Functions, attribute IDs — purple
    base0E = "#fc618d"; # Keywords, storage — pink/red (same hue as base08)
    base0F = "#fef20a"; # Deprecated, tags — bright yellow
    # Extended base24 shades
    base10 = "#191919"; # Darkest background
    base11 = "#222222"; # Darker background (alias of base00)
    base12 = "#FC618D"; # Alert red
    base13 = "#FCE566"; # Alert yellow
    base14 = "#7BD88F"; # Alert green
    base15 = "#5AD4E6"; # Alert cyan
    base16 = "#948AE3"; # Alert purple
    base17 = "#FD9353"; # Alert orange
  };

  # Extra colours used in this config that fall outside the base24 spec.
  extras = {
    # Lighter lavender — used as git branch colour in Starship
    lavender = "#AB9DF2";
    # Dim yellow — exported as the $yellow shell alias (intentionally distinct from base0A)
    yellowDim = "#fcd566";
    # Extra dark midtone — exported as the $base8x0c shell alias
    darkMidtone = "#2b2b2b";
  };
in
  palette // {inherit extras;}
