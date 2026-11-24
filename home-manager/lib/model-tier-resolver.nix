# Command prefix for scripts/resolve-model-tiers.py bound to this repo's tier
# families and floors (lib/model-tiers.nix). Activation snippets append
# `--catalog <models_cache.json>` and a subcommand; see the script's --help.
{pkgs}: let
  tiers = pkgs.writeText "model-tiers.json" (builtins.toJSON (import ./model-tiers.nix).openai);
in "${pkgs.python3}/bin/python3 -I ${../../scripts/resolve-model-tiers.py} --tiers ${tiers}"
