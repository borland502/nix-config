# KDE Plasma Desktop Environment configuration
{ config, lib, pkgs, ... }:

{
  # Disable X11 as we're using Wayland
  services.xserver.enable = false;

  # Enable KDE Plasma Desktop Environment
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
    };
    defaultSession = "plasma";
  };
  
  services.desktopManager.plasma6.enable = true;

  # Remove Spectacle from the default Plasma apps bundle
  environment.plasma6.excludePackages = with pkgs.kdePackages; [ spectacle ];

  # Enable touchpad support (enabled by default in most desktop managers)
  # services.xserver.libinput.enable = true;
}
