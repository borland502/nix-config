# Turn KRdp on by default, without going through the Remote Desktop panel.
#
# This is a *seed*, not a declaration: every step below is skipped if the thing
# already exists, so System Settings stays authoritative once a human has
# touched it. A fresh Plasma host comes up with remote desktop already enabled;
# a host where it has been deliberately turned off stays off.
#
# The whole module no-ops unless krdpserver is on PATH, so it is inert on the
# Linux hosts that do not run Plasma (KRdp needs KWin's fake-input and
# screencast Wayland protocols — it does not work on other compositors, and
# not on X11 at all).
#
# What makes this declarable at all is SystemUserEnabled: KRdp 6.7+ can
# authenticate against the system account through PAM (service "login", present
# on both NixOS and Arch) instead of a per-user password in KWallet. There is
# therefore no secret to seed — which is why this can be a config file rather
# than a GUI step.
{
  config,
  lib,
  pkgs,
  ...
}: let
  stateDir = "${config.home.homeDirectory}/.local/share/krdpserver";
  rc = "${config.home.homeDirectory}/.config/krdpserverrc";

  # The unit the Remote Desktop panel itself toggles. Arch ships it as a real
  # file; on NixOS it is synthesized by systemd's xdg-autostart generator from
  # the .desktop file krdp installs. Either way this is the name to enable, so
  # the panel and this module agree on one switch rather than racing two.
  unit = "app-org.kde.krdpserver.service";

  coreutils = "${pkgs.coreutils}/bin";
  gnugrep = "${pkgs.gnugrep}/bin";
  gawk = "${pkgs.gawk}/bin";
in {
  # NB: no early `exit` anywhere in here. Home Manager concatenates every
  # activation snippet into one script, so an `exit` would abort the whole
  # activation and silently skip every step ordered after this one. The
  # applicability check is therefore a wrapping conditional, not a guard clause.
  home.activation.seedKrdp = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if PATH="${config.home.profileDirectory}/bin:$PATH" command -v krdpserver >/dev/null 2>&1; then

      # TLS is mandatory for RDP; krdpserver refuses to start without a cert.
      # Self-signed is what the panel's own "generate" button produces too, so
      # this only front-runs a manual step rather than lowering the bar.
      if [ ! -s "${stateDir}/krdp.crt" ] || [ ! -s "${stateDir}/krdp.key" ]; then
        $DRY_RUN_CMD ${coreutils}/mkdir -p "${stateDir}"
        $DRY_RUN_CMD ${pkgs.openssl}/bin/openssl req -x509 -nodes \
          -newkey rsa:4096 -sha256 -days 3650 \
          -subj "/CN=$(${coreutils}/uname -n)" \
          -keyout "${stateDir}/krdp.key" \
          -out "${stateDir}/krdp.crt" 2>/dev/null
        $DRY_RUN_CMD ${coreutils}/chmod 0600 "${stateDir}/krdp.key"
        echo "krdp: generated self-signed certificate in ${stateDir}"
      fi

      # Key-wise merge, not a write-if-absent.
      #
      # A whole-file guard latches: krdpserver writes its own krdpserverrc the
      # first time it runs (the panel's "generate certificate" step does it
      # too), carrying only Certificate/CertificateKey. If that happens before
      # this ever runs — which is exactly what a fresh install does, since the
      # activation's check runs before the user has opened the panel — the file
      # now exists, the guard skips, and Autostart/SystemUserEnabled are never
      # added. The server then starts and immediately exits with "No users
      # configured for login. Either pass a username/password or configure
      # users using kcm_krdp", with no way out short of editing the file.
      #
      # So each key is seeded independently, and only when it is missing. An
      # existing value is never rewritten, which is what keeps System Settings
      # authoritative (the same rule plasma-manager follows in home.nix).
      if [ ! -e "${rc}" ]; then
        $DRY_RUN_CMD ${coreutils}/printf '%s\n' '[General]' > "${rc}"
        $DRY_RUN_CMD ${coreutils}/chmod 0600 "${rc}"
      fi

      krdp_ensure_key() {
        local key="$1" val="$2"

        if ${gnugrep}/grep -qE "^$key=" "${rc}"; then
          return 0
        fi

        # Inserted directly after [General] rather than appended, or the key
        # would land in whatever section happens to be last in the file.
        if ${gnugrep}/grep -qE '^\[General\]' "${rc}"; then
          $DRY_RUN_CMD ${gawk}/awk -v k="$key" -v v="$val" '
            { print }
            /^\[General\]/ && !ins { print k "=" v; ins = 1 }
          ' "${rc}" > "${rc}.hm-tmp" && $DRY_RUN_CMD ${coreutils}/mv "${rc}.hm-tmp" "${rc}"
        else
          $DRY_RUN_CMD ${coreutils}/printf '%s\n%s=%s\n' '[General]' "$key" "$val" >> "${rc}"
        fi

        $DRY_RUN_CMD ${coreutils}/chmod 0600 "${rc}"
        echo "krdp: set $key in ${rc}"
      }

      krdp_ensure_key Autostart true
      krdp_ensure_key Certificate '${stateDir}/krdp.crt'
      krdp_ensure_key CertificateKey '${stateDir}/krdp.key'
      krdp_ensure_key SystemUserEnabled true

      # `systemctl --user enable` is what the panel does; matching it keeps one
      # source of truth. Guarded because a switch can run without a user bus,
      # and on NixOS the generated unit only exists once the session has been up.
      if ${pkgs.systemd}/bin/systemctl --user cat ${unit} >/dev/null 2>&1; then
        if ! ${pkgs.systemd}/bin/systemctl --user is-enabled --quiet ${unit} 2>/dev/null; then
          $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user enable ${unit} >/dev/null 2>&1 || true
          echo "krdp: enabled ${unit}"
        fi
      fi
    fi
  '';
}
