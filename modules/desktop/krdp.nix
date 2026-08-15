# KRdp — Plasma's own RDP server (FreeRDP 3 + PipeWire), driven from
# System Settings > Remote Desktop.
#
# This is the Wayland-native replacement for xrdp, which cannot work here at
# all: xrdp drives an X server, while KRdp captures the live KWin session
# through the xdg-desktop-portal RemoteDesktop/ScreenCast interfaces and
# injects input over the `org_kde_kwin_fake_input` Wayland protocol.
#
# The prerequisites are already satisfied by the rest of the linux host:
#   - PipeWire            <- ../audio/pulseaudio.nix
#   - xdg-desktop-portal-kde and xdg.autostart <- services.desktopManager.plasma6
{pkgs, ...}: {
  # plasma6 lists krdp among its *optional* packages, so it drops out the moment
  # anything is added to environment.plasma6.excludePackages. Name it explicitly.
  environment.systemPackages = [pkgs.kdePackages.krdp];

  # 3389 is deliberately NOT opened. Reach it by forwarding over the already
  # enabled sshd instead:
  #
  #   ssh -N -L 3389:localhost:3389 linux
  #
  # then point the RDP client at localhost:3389. That puts the session behind
  # ssh host-key verification and key auth, rather than behind the single
  # username/password stored in KWallet by the Remote Desktop panel — which is
  # the *only* thing guarding a full desktop-takeover channel otherwise.
  #
  # The firewall is doing the real work here: krdpserver binds 0.0.0.0 and has
  # no address setting to narrow it (the KCM exposes listenPort but not a bind
  # address), so nothing but a closed port keeps it off the LAN.

  # KRdp encodes H.264 through VA-API when a driver is present and falls back to
  # openh264 on the CPU otherwise. This host is kvm-intel with no
  # hardware.graphics.extraPackages set, so it is currently on the software
  # path; adding pkgs.intel-media-driver there would move encoding onto the iGPU.
}
