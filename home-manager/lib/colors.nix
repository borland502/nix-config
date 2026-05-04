# Single source of truth: chezmoi/dot_config/colors/monokai.toml
# Parsed at Nix eval time via builtins.fromTOML.
# Used by starship-settings.nix, zsh.nix, home-wsl.nix, and home-darwin.nix.
let
  raw = builtins.fromTOML (builtins.readFile ../../chezmoi/dot_config/colors/monokai.toml);
in
  raw.palette // {inherit (raw) extras;}
