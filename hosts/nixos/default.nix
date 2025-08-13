# NixOS host configuration
{ config, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan
    # You'll need to generate this with: nixos-generate-config
    # ./hardware-configuration.nix
  ];

  # Host-specific settings
  networking.hostName = "nixos";

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    # Add any nixos-specific packages here
  ];

  # System state version
  system.stateVersion = "25.05";
}
