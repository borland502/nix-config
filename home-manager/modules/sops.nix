# Home-manager sops-nix configuration
# Decrypts user-level secrets at home-manager activation time using an age key.
# Generate a key with: age-keygen -o ~/.config/sops/age/keys.txt
#
# Bootstrap order on a new machine: run scripts/provision-secrets.sh FIRST to
# write the age key, then switch.  That script is standalone shell and needs no
# prior switch, so the key is always available by the time this module runs.
#
# This block used to be guarded by `builtins.pathExists ageKeyFile`, which is
# always false under the flake's pure evaluation (absolute $HOME paths are not
# readable there) — so sops-nix silently installed nothing at all.  If you ever
# genuinely need to switch before the key exists, flip secretsEnabled to false
# for that one switch instead of reintroducing a pathExists check.
{
  config,
  pkgs,
  lib,
  ...
}: let
  ageKeyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  secretsEnabled = true;
in {
  sops = lib.mkIf secretsEnabled {
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

      # Sonarr API key for the internal instance.  Its base URL lives in the
      # same file as arr/sonarr_base_url — encrypted, matching how the jira and
      # confluence base URLs are handled — and is deliberately not materialized.
      "arr/sonarr_api_key" = {
        sopsFile = ../../secrets/arr.yaml;
        path = "${config.home.homeDirectory}/.config/arr/sonarr.key";
      };

      # Prowlarr API key.  Prowlarr is the indexer proxy behind Sonarr, so this
      # is the key that reaches the indexer definitions themselves.
      "arr/prowlarr_api_key" = {
        sopsFile = ../../secrets/arr.yaml;
        path = "${config.home.homeDirectory}/.config/arr/prowlarr.key";
      };

      # Dedicated remoting key: the single credential for reaching these hosts
      # over ssh, and through an ssh tunnel for KRdp. It is not a general
      # identity — no service or forge auth uses it, so it can be rotated by
      # regenerating this one secret and the matching .pub.
      #
      # The public half is tracked in the clear at
      # chezmoi/dot_config/ssh/remoting-key.pub and is what gets authorized on
      # every host (modules/services/sshd.nix on NixOS,
      # chezmoi/run_onchange_provision-linux-host.sh.tmpl elsewhere).
      #
      # mode 0600 is mandatory: ssh refuses a private key that is group- or
      # world-readable, and sops-nix defaults to 0400 for the *owner* only,
      # which ssh accepts but which surprises anything that tries to rewrite it.
      # Synology NAS (alisaie) share credentials.
      #
      # Only the SMB half is materialized. The admin credential stays encrypted
      # and is read on demand — nothing should be handed an admin password
      # automatically, and it was needed exactly once, to authorize the remoting
      # key above. Same arrangement as secrets/rclone-gdrive.json:
      #   sops -d secrets/alisaie.yaml | yq -r .alisaie.admin_password
      #
      # mode 0600 rather than sops-nix's 0400 default: rclone reads this at
      # every mount, and 0400 invites a later "fix" that rewrites it wholesale.
      "alisaie/smb_password" = {
        sopsFile = ../../secrets/alisaie.yaml;
        path = "${config.home.homeDirectory}/.config/rclone/alisaie-smb-password";
        mode = "0600";
      };

      # KeePassXC master password.  The database at
      # ~/.local/share/keypass/secrets.kdbx needs all three of password, key
      # file (~/.local/state/keepass/secrets.keyx) and a YubiKey slot-2
      # challenge-response; only the password is a secret this repo can hold.
      # The key file is deliberately kept out of sops: it is mirrored to Drive
      # by sync-to-gdrive for portability, so putting it here would create a
      # second, diverging copy.
      #
      # mode 0600 rather than sops-nix's 0400 default, for the same reason as
      # alisaie/smb_password: ~/.local/bin/keepass redirects this file onto
      # keepassxc-cli's stdin on every call, and 0400 invites a later "fix"
      # that rewrites it wholesale.
      "keepassxc/master_password" = {
        sopsFile = ../../secrets/keepassxc.yaml;
        path = "${config.home.homeDirectory}/.config/keepass/password";
        mode = "0600";
      };

      "remoting/ssh_private_key" = {
        sopsFile = ../../secrets/remoting-ssh.yaml;
        path = "${config.home.homeDirectory}/.ssh/id_remoting";
        mode = "0600";
      };
    };
  };

  # rclone gdrive OAuth client credentials live encrypted at
  # secrets/rclone-gdrive.json ({installed:{client_id, client_secret}}).
  # Only the *static* app credentials are stored — the per-device OAuth token
  # is intentionally NOT versioned, so it never needs re-encrypting as it
  # refreshes, and this file never drifts. Nothing decrypts it automatically.
  #
  # Fresh machine (no ~/.config/rclone/rclone.conf yet): read the client creds
  # from the encrypted file, recreate the remote, then authorize in a browser:
  #   id=$(sops -d secrets/rclone-gdrive.json  | jq -r .installed.client_id)
  #   sec=$(sops -d secrets/rclone-gdrive.json | jq -r .installed.client_secret)
  #   rclone config create gdrive drive scope=drive \
  #     client_id="$id" client_secret="$sec"   # opens browser to authorize
  # If the remote already exists but its token is missing/expired, just:
  #   rclone config reconnect gdrive:
  #
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

    # The ssh host inventory. This repo is PUBLIC, and hosts.toml is a complete
    # map of the home network — every host, address, MAC, login and remoting
    # key path — so it lives encrypted at secrets/hosts.toml rather than in the
    # chezmoi tree. Nothing in it is a credential; the exposure it prevents is
    # reconnaissance, which is why encryption was enough and rotation was not
    # required.
    #
    # The git history was deliberately NOT rewritten (decision 2026-08-28). The
    # plaintext inventory is still readable in every commit before this one, on
    # a public remote, and encrypting it stops future exposure only. That was
    # judged the better trade: the already-published topology matters less than
    # the repo's history and coherence, which a force-push would damage. Do not
    # assume a name or address found in an old commit is secret.
    #
    # Encrypted with --input-type binary: sops' native TOML handling would
    # discard the comments, and in this file the comments carry more operational
    # knowledge than the values do (why a host has no `mac`, why an address is
    # raw rather than an FQDN, which guests are static and therefore immune to a
    # DHCP reservation). Binary mode treats the file as opaque bytes and returns
    # it byte-identical.
    decryptSshHosts = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _age_key="${config.home.homeDirectory}/.config/sops/age/keys.txt"
      if [ -f "$_age_key" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.config/ssh"
        SOPS_AGE_KEY_FILE="$_age_key" \
          ${pkgs.sops}/bin/sops --decrypt \
          --input-type binary --output-type binary \
          ${../../secrets/hosts.toml} \
          > "${config.home.homeDirectory}/.config/ssh/hosts.toml"
        ${pkgs.coreutils}/bin/chmod 600 "${config.home.homeDirectory}/.config/ssh/hosts.toml"
      fi
    '';

    # Render the decrypted inventory into an ssh_config fragment that
    # ~/.ssh/config Includes.
    #
    # This used to be `programs.ssh.settings`, evaluated from the repo copy by
    # home-manager/common.nix. That is no longer possible: flake eval is pure,
    # so it cannot decrypt, and the plaintext it used to read no longer exists.
    # Rendering therefore moved from eval time to activation time.
    #
    # `desktop` and `mac` are stripped for the same reason common.nix stripped
    # them: ssh_config is not extensible, and ONE unrecognised keyword makes
    # every ssh invocation fail — not just one to the host that declared it.
    renderSshHostConfig = lib.hm.dag.entryAfter ["decryptSshHosts"] ''
      _hosts="${config.home.homeDirectory}/.config/ssh/hosts.toml"
      _dir="${config.home.homeDirectory}/.ssh/config.d"
      if [ -r "$_hosts" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$_dir"
        if ${pkgs.taplo}/bin/taplo get -f "$_hosts" -o json 'hosts' \
             | ${pkgs.jq}/bin/jq -r '
                 to_entries[]
                 | "Host \(.key)",
                   ( .value
                     | to_entries[]
                     | select(.key != "desktop" and .key != "mac")
                     | "  \(.key) \(.value)" ),
                   ""
               ' > "$_dir/hosts.tmp"; then
          ${pkgs.coreutils}/bin/mv "$_dir/hosts.tmp" "$_dir/hosts"
          ${pkgs.coreutils}/bin/chmod 600 "$_dir/hosts"
        else
          # Leave the previous fragment in place. A half-written or empty
          # include silently strips every host alias, and the failure shows up
          # later as "Could not resolve hostname tifa" rather than as a
          # decryption or parse error.
          ${pkgs.coreutils}/bin/rm -f "$_dir/hosts.tmp"
          echo "renderSshHostConfig: could not parse $_hosts; kept previous ~/.ssh/config.d/hosts" >&2
        fi
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
