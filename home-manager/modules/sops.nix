# Home-manager sops-nix configuration
# Decrypts user-level secrets at home-manager activation time using an age key.
# Generate a key with: age-keygen -o ~/.config/sops/age/keys.txt
{config, ...}: {
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFormat = "yaml";

    secrets."ops_agent/jira_base_url" = {
      sopsFile = ../../secrets/ops-agent.yaml;
      path = "${config.home.homeDirectory}/.config/ops-agent/jira-base-url";
    };

    # ops_agent/jira_token: Will be added after provisioning age key and encrypting secret.
    # See ai-tools/skills/sec-sops-encrypt/ for the workflow.
  };
}
