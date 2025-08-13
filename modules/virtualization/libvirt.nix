# Virtualization with libvirt and virt-manager
{ config, lib, pkgs, ... }:

{
  # Enable virtualization
  programs.virt-manager.enable = true;
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # Add user to libvirtd group
  users.groups.libvirtd.members = [ "jhettenh" ];
}
