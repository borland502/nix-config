# Home-manager sops-nix configuration
# Decrypts user-level secrets at home-manager activation time using an age key.
# Generate a key with: age-keygen -o ~/.config/sops/age/keys.txt
#
# The entire sops block is guarded by builtins.pathExists so that an initial
# install (where the age key has not yet been provisioned) can complete
# home-manager switch without errors.  After provision-secrets.sh writes the
# key, the next switch will find the key present and decrypt all secrets.
{
  config,
  pkgs,
  lib,
  ...
}: let
  ageKeyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  ageKeyPresent = builtins.pathExists ageKeyFile;
in {
  sops = lib.mkIf ageKeyPresent {
    age.keyFile = ageKeyFile;
    defaultSopsFormat = "yaml";

    secrets = {
      "ops_agent/jira_base_url" = {
        sopsFile = ../../secrets/ops-agent.yaml;
        path = "${config.home.homeDirectory}/.config/ops-agent/jira-base-url";
      };
      "ops_agent/jira_token" = {
        sopsFile = ../../secrets/ops-agent.yaml;
        path = "${config.home.homeDirectory}/.config/ops-agent/jira-token";
      };
      "ops_agent/confluence_base_url" = {
        sopsFile = ../../secrets/ops-agent.yaml;
        path = "${config.home.homeDirectory}/.config/confluence/base-url";
      };
      "ops_agent/confluence_token" = {
        sopsFile = ../../secrets/ops-agent.yaml;
        path = "${config.home.homeDirectory}/.config/confluence/token";
      };
    };
  };

  # Whole-file TOML secrets: sops-nix extracts individual keys, but these tools
  # expect a complete config.toml, so we decrypt the whole file via activation.
  home.activation = {
    decryptGkionConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _age_key="${config.home.homeDirectory}/.config/sops/age/keys.txt"
      if [ -f "$_age_key" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.config/gkion"
        SOPS_AGE_KEY_FILE="$_age_key" \
          ${pkgs.sops}/bin/sops --decrypt \
          ${../../secrets/gkion.toml} \
          > "${config.home.homeDirectory}/.config/gkion/config.toml"
        ${pkgs.coreutils}/bin/chmod 600 "${config.home.homeDirectory}/.config/gkion/config.toml"
      fi
    '';

    decryptTechnitiumConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _age_key="${config.home.homeDirectory}/.config/sops/age/keys.txt"
      if [ -f "$_age_key" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.config/technitiumdns-cli"
        SOPS_AGE_KEY_FILE="$_age_key" \
          ${pkgs.sops}/bin/sops --decrypt \
          ${../../secrets/technitiumdns-cli.toml} \
          > "${config.home.homeDirectory}/.config/technitiumdns-cli/config.toml"
        ${pkgs.coreutils}/bin/chmod 600 "${config.home.homeDirectory}/.config/technitiumdns-cli/config.toml"
      fi
    '';
  };
}
