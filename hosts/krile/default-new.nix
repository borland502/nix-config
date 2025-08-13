# Krile host-specific configuration
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Host-specific settings
  networking.hostName = "krile";

  # Enable rclone mounts using the custom module
  services.rclone-mounts = {
    enable = true;
    mounts.gdrive = {
      remote = "gdrive:";
      mountPoint = "/home/jhettenh/.state/remotes/gdrive";
      user = "jhettenh";
    };
  };

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    # Add any krile-specific packages here
  ];

  # System state version
  system.stateVersion = "25.05";
}
