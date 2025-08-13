# Reusable rclone mount service module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rclone-mounts;
in
{
  options.services.rclone-mounts = {
    enable = mkEnableOption "rclone mount services";
    
    mounts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          remote = mkOption {
            type = types.str;
            description = "Rclone remote name (e.g., 'gdrive:')";
          };
          mountPoint = mkOption {
            type = types.str;
            description = "Local mount point path";
          };
          user = mkOption {
            type = types.str;
            default = "jhettenh";
            description = "User to run the service as";
          };
          extraFlags = mkOption {
            type = types.listOf types.str;
            default = [ "--vfs-cache-mode" "writes" "--allow-other" ];
            description = "Additional rclone flags";
          };
        };
      });
      default = {};
      description = "Rclone mounts to configure";
    };
  };

  config = mkIf cfg.enable {
    # Enable FUSE for mounting
    programs.fuse.userAllowOther = true;
    
    # Ensure rclone is available
    environment.systemPackages = [ pkgs.rclone ];
    
    # Create systemd services for each mount
    systemd.services = mapAttrs' (name: mount: 
      nameValuePair "rclone-${name}" {
        description = "RClone mount for ${mount.remote}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          User = mount.user;
          Group = "users";
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mount.mountPoint}";
          ExecStart = "${pkgs.rclone}/bin/rclone mount ${mount.remote} ${mount.mountPoint} ${concatStringsSep " " mount.extraFlags} --daemon";
          ExecStop = "/run/wrappers/bin/fusermount3 -u ${mount.mountPoint}";
          Restart = "on-failure";
          RestartSec = "10s";
          Environment = [ "PATH=${pkgs.fuse3}/bin:$PATH" ];
          # Additional permissions for FUSE mounting
          PrivateDevices = false;
          DeviceAllow = [ "/dev/fuse rw" ];
          NoNewPrivileges = false;
        };
      }
    ) cfg.mounts;
  };
}
