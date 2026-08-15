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

      # Seeded only when absent. Rewriting it would fight the panel, which is
      # the failure mode already documented for plasma-manager in home.nix.
      if [ ! -e "${rc}" ]; then
        $DRY_RUN_CMD ${coreutils}/printf '%s\n' \
          '[General]' \
          'Autostart=true' \
          'Certificate=${stateDir}/krdp.crt' \
          'CertificateKey=${stateDir}/krdp.key' \
          'SystemUserEnabled=true' > "${rc}"
        $DRY_RUN_CMD ${coreutils}/chmod 0600 "${rc}"
        echo "krdp: seeded ${rc} (autostart on, system-user auth)"
      fi

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
