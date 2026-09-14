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

      # InfluxDB write token for the local telegraf agent
      # (home-manager/modules/telegraf.nix). Stored already formatted as a
      # systemd EnvironmentFile line -- `INFLUX_TOKEN=...` -- so the unit points
      # straight at this path. The token must never reach telegraf.conf itself:
      # that file is rendered into the world-readable Nix store, while this
      # materializes at 0400 under $HOME.
      #
      # Scope is write-only on the `telegraf` bucket of org `proxmox`; it is NOT
      # the all-access token Proxmox uses for its own metric export, so the two
      # rotate independently.
      "telegraf/influx_env" = {
        sopsFile = ../../secrets/telegraf.yaml;
        path = "${config.home.homeDirectory}/.config/telegraf/influx.env";
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

      # KeePassXC composite key. The vault at ~/gdrive/keepass/secrets.kdbx
      # needs all three of master password, key file and a YubiKey slot-2
      # challenge-response. Two of the three are carried here; the YubiKey is
      # the factor that never leaves hardware, and is what makes holding the
      # other two acceptable at all.
      #
      # mode 0600 rather than sops-nix's 0400 default, for the same reason as
      # alisaie/smb_password: ~/.local/bin/keepass feeds these to
      # keepassxc-cli on every call, and 0400 invites a later "fix" that
      # rewrites them wholesale.
      "keepassxc/master_password" = {
        sopsFile = ../../secrets/keepassxc.yaml;
        path = "${config.home.homeDirectory}/.config/keepass/password";
        mode = "0600";
      };

      # The key file was previously kept OUT of sops, on the reasoning that
      # sync-to-gdrive already mirrored it to Drive and a second copy would
      # diverge. That had two costs: darwin ended up with no key file at all,
      # so `keepass` could not run there, and it parked a second composite-key
      # factor next to the vault on Drive. It is carried here instead, and the
      # Drive copy is retired once this has materialized on both hosts — see
      # ~/.cache/claude/2026-09-08-keepass-vault-unification-plan.md.
      "keepassxc/key_file" = {
        sopsFile = ../../secrets/keepassxc.yaml;
        path = "${config.home.homeDirectory}/.local/state/keepass/secrets.keyx";
        mode = "0600";
      };

      "remoting/ssh_private_key" = {
        sopsFile = ../../secrets/remoting-ssh.yaml;
        path = "${config.home.homeDirectory}/.ssh/id_remoting";
        mode = "0600";
      };
    };
  };

  # Chrome bookmark bar source of truth. Like secrets/hosts.toml, nothing in
  # here is a credential -- the exposure it prevents is reconnaissance: the
  # Homelab links are internal LAN hostnames/IPs and the Work links are
  # internal-only CMS/MDP endpoints, and this repo is PUBLIC (CLAUDE.md: never
  # commit an internal URL/hostname to it in the clear). Encrypted the same
  # way and for the same reason as hosts.toml -- see decryptSshHosts's comment
  # above for the binary-mode rationale (preserves the source comments) and
  # the "write to tmp then mv" rationale (a failed decrypt must never truncate
  # the previous copy).
  #
  # `path` in each [[link]] entry is a "/"-separated bookmark-bar folder
  # breadcrumb; home-manager/modules/chrome-bookmarks.jq turns the flat list
  # into Chrome's native folder tree. Edit with `sops secrets/bookmarks.toml`.

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
  #
  # Every decrypt below writes to a temp file and moves it into place, rather
  # than redirecting sops' stdout at the destination. A plain `sops -d > dest`
  # truncates dest BEFORE sops runs, so any decryption failure -- a corrupt
  # ciphertext, a missing recipient, a bad key -- replaces a working config
  # with an empty file. That is not hypothetical: a merge of secrets/hosts.toml
  # on 2026-09-05 kept the branch's ciphertext with main's wrapped data key, and
  # the file stopped decrypting; only the fact that nothing had re-activated
  # since kept the deployed ssh inventory intact. Failing loudly and leaving the
  # previous copy alone is strictly better, and matches what
  # renderSshHostConfig below already does with its own output.
  home.activation = {
    decryptGkionConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _age_key="${config.home.homeDirectory}/.config/sops/age/keys.txt"
      if [ -f "$_age_key" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.config/gkion"
        _dest="${config.home.homeDirectory}/.config/gkion/config.toml"
        _tmp="$_dest.tmp"
        if SOPS_AGE_KEY_FILE="$_age_key" \
          ${pkgs.sops}/bin/sops --decrypt \
          ${../../secrets/gkion.toml} \
          > "$_tmp"; then
          ${pkgs.coreutils}/bin/chmod 600 "$_tmp"
          ${pkgs.coreutils}/bin/mv "$_tmp" "$_dest"
        else
          ${pkgs.coreutils}/bin/rm -f "$_tmp"
          echo "decryptGkionConfig: sops could not decrypt secrets/gkion.toml; kept the previous $_dest" >&2
        fi
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
        _dest="${config.home.homeDirectory}/.config/ssh/hosts.toml"
        _tmp="$_dest.tmp"
        if SOPS_AGE_KEY_FILE="$_age_key" \
          ${pkgs.sops}/bin/sops --decrypt \
          --input-type binary --output-type binary \
          ${../../secrets/hosts.toml} \
          > "$_tmp"; then
          ${pkgs.coreutils}/bin/chmod 600 "$_tmp"
          ${pkgs.coreutils}/bin/mv "$_tmp" "$_dest"
        else
          ${pkgs.coreutils}/bin/rm -f "$_tmp"
          echo "decryptSshHosts: sops could not decrypt secrets/hosts.toml; kept the previous $_dest" >&2
        fi
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
        # Each stage is checked separately, and the result must be non-empty.
        # A pipeline's exit status is only its LAST command: if taplo fails it
        # writes nothing, jq reads empty input and still exits 0, and an EMPTY
        # fragment would be installed -- the very outcome this guard exists to
        # prevent.
        if _json=$(${pkgs.taplo}/bin/taplo get -f "$_hosts" -o json 'hosts') \
           && printf '%s' "$_json" \
             | ${pkgs.jq}/bin/jq -r '
                 to_entries[]
                 | "Host \(.key)",
                   ( .value
                     | to_entries[]
                     | select(.key != "desktop" and .key != "mac")
                     | "  \(.key) \(.value)" ),
                   ""
               ' > "$_dir/hosts.tmp" \
           && [ -s "$_dir/hosts.tmp" ]; then
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
        _dest="${config.home.homeDirectory}/.config/technitiumdns-cli/config.toml"
        _tmp="$_dest.tmp"
        if SOPS_AGE_KEY_FILE="$_age_key" \
          ${pkgs.sops}/bin/sops --decrypt \
          ${../../secrets/technitiumdns-cli.toml} \
          > "$_tmp"; then
          ${pkgs.coreutils}/bin/chmod 600 "$_tmp"
          ${pkgs.coreutils}/bin/mv "$_tmp" "$_dest"
        else
          ${pkgs.coreutils}/bin/rm -f "$_tmp"
          echo "decryptTechnitiumConfig: sops could not decrypt secrets/technitiumdns-cli.toml; kept the previous $_dest" >&2
        fi
      fi
    '';

    decryptBookmarks = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _age_key="${config.home.homeDirectory}/.config/sops/age/keys.txt"
      if [ -f "$_age_key" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.config/bookmarks"
        _dest="${config.home.homeDirectory}/.config/bookmarks/bookmarks.toml"
        _tmp="$_dest.tmp"
        if SOPS_AGE_KEY_FILE="$_age_key" \
          ${pkgs.sops}/bin/sops --decrypt \
          --input-type binary --output-type binary \
          ${../../secrets/bookmarks.toml} \
          > "$_tmp"; then
          ${pkgs.coreutils}/bin/chmod 600 "$_tmp"
          ${pkgs.coreutils}/bin/mv "$_tmp" "$_dest"
        else
          ${pkgs.coreutils}/bin/rm -f "$_tmp"
          echo "decryptBookmarks: sops could not decrypt secrets/bookmarks.toml; kept the previous $_dest" >&2
        fi
      fi
    '';

    # Render the decrypted link list into Chrome's native Bookmarks JSON and
    # drop it straight into Chrome's profile -- there is no policy-level lever
    # for bookmarks the way there is for Vivaldi's extension allowlist (see
    # chezmoi/run_onchange_provision-linux-host.sh.tmpl section 10), so this
    # writes the profile file directly, the same way a bookmark sync tool
    # would.
    #
    # Guarded on Chrome not currently running: Chrome only writes Bookmarks
    # back out on exit, so overwriting it while Chrome is open just means our
    # write gets silently discarded at the next quit (the same "rewrites on
    # exit" hazard called out for Vivaldi's Preferences file). Skipping is
    # strictly better than racing it.
    #
    # Only the bookmark_bar root is ours; other/synced/trash are read back
    # from whatever Bookmarks file is already there (or defaulted) and passed
    # through untouched, so bookmarks added by hand outside the bar survive an
    # activation.
    #
    # Flatpak Chrome and a natively-packaged Chrome keep separate profile
    # directories; try the flatpak path first since that's how Chrome is
    # provisioned on generic Linux hosts (see nixosOnlyPackages in
    # home-manager/profiles/desktop-linux.nix).
    renderChromeBookmarks = lib.hm.dag.entryAfter ["decryptBookmarks"] ''
      _links_toml="${config.home.homeDirectory}/.config/bookmarks/bookmarks.toml"
      _profile_dir=""
      # Home Manager's activation script runs with its own narrow PATH (nix
      # store paths only -- see the `export PATH=` line at the top of the
      # generated activate script), so host tools like flatpak and Chrome
      # itself are invoked by absolute path here rather than bare name, the
      # same way hostHelperShim in home-manager/profiles/desktop-linux.nix
      # hardcodes /usr/bin/* for host binaries it re-execs.
      if [ -x /usr/bin/flatpak ] && /usr/bin/flatpak info com.google.Chrome >/dev/null 2>&1; then
        _profile_dir="${config.home.homeDirectory}/.var/app/com.google.Chrome/config/google-chrome/Default"
      elif [ -x /usr/bin/google-chrome-stable ] || [ -x /usr/bin/google-chrome ] \
        || [ -x "${config.home.homeDirectory}/.nix-profile/bin/google-chrome-stable" ]; then
        # The last check covers a NixOS/WSL host, where google-chrome comes
        # from nixosOnlyPackages in home-manager/profiles/desktop-linux.nix
        # and lands in the per-user nix profile rather than /usr/bin.
        _profile_dir="${config.home.homeDirectory}/.config/google-chrome/Default"
      fi

      if [ -r "$_links_toml" ] && [ -n "$_profile_dir" ]; then
        if ${pkgs.procps}/bin/pgrep -x chrome >/dev/null 2>&1 || ${pkgs.procps}/bin/pgrep -f 'google-chrome' >/dev/null 2>&1; then
          echo "renderChromeBookmarks: Chrome is running; skipping (it would overwrite this on exit). Re-run \`task switch\` after closing it." >&2
        else
          ${pkgs.coreutils}/bin/mkdir -p "$_profile_dir"
          _dest="$_profile_dir/Bookmarks"
          _tmp="$_dest.tmp"
          _now_us=$(( ($(${pkgs.coreutils}/bin/date +%s) + 11644473600) * 1000000 ))
          _default_root='{"children":[],"date_added":"0","date_last_used":"0","date_modified":"0","guid":"00000000-0000-4000-8000-000000000000","id":"0","name":"","type":"folder"}'
          if _links_json=$(${pkgs.taplo}/bin/taplo get -f "$_links_toml" -o json 'link') \
             && _bar=$(${pkgs.jq}/bin/jq -n --argjson links "$_links_json" --arg now_us "$_now_us" \
                 -f ${../../home-manager/modules/chrome-bookmarks.jq}) \
             && _existing=$(
                 if [ -f "$_dest" ]; then ${pkgs.coreutils}/bin/cat "$_dest"; else printf '{}'; fi
               ) \
             && ${pkgs.jq}/bin/jq \
                 --argjson bar "$_bar" \
                 --argjson default_root "$_default_root" \
                 --arg now_us "$_now_us" \
                 '{
                    version: 1,
                    checksum: "00000000000000000000000000000000",
                    roots: {
                      bookmark_bar: ($bar + {id: "1", guid: "0bc5d13f-2cba-5d74-951f-3f233fe6c908", name: "Bookmarks", type: "folder", date_added: $now_us, date_modified: $now_us}),
                      other: (.roots.other // ($default_root + {id: "2", name: "Other bookmarks"})),
                      synced: (.roots.synced // ($default_root + {id: "3", name: "Mobile bookmarks"})),
                      trash: (.roots.trash // ($default_root + {id: "4", name: "Trash"}))
                    }
                  }' <<<"$_existing" > "$_tmp"
          then
            ${pkgs.coreutils}/bin/mv "$_tmp" "$_dest"
            echo "renderChromeBookmarks: wrote $_dest"
          else
            ${pkgs.coreutils}/bin/rm -f "$_tmp"
            echo "renderChromeBookmarks: could not render bookmarks.toml; kept previous $_dest" >&2
          fi
        fi
      fi
    '';
  };
}
