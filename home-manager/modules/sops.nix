# Home-manager sops-nix configuration
# Decrypts user-level secrets at home-manager activation time using an age key.
# Generate a key with: age-keygen -o ~/.config/sops/age/keys.txt
{config, ...}: {
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFormat = "yaml";

    # Declare secrets here as needed, for example:
    # secrets."github-token" = {
    #   sopsFile = ../../secrets/user-secrets.yaml;
    # };
  };
}
