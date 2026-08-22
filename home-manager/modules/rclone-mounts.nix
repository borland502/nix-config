{
  config,
  lib,
  pkgs,
  ...
}: let
  homeDirectory = config.home.homeDirectory;

  # chezmoi deploys the script (chezmoi/dot_local/bin/executable_rclone-mount),
  # not nix — so this is a plain path, not a store path, and every unit guards on
  # its existence rather than assuming it. Same arrangement as gdrive-sync.nix.
  mountScript = "${homeDirectory}/.local/bin/rclone-mount";

  # systemd user units do not inherit the login shell's environment, and the
  # script's `#!/usr/bin/env zsh` needs a PATH to resolve zsh through. Nix
  # profile first so rclone and zsh match an interactive run even on a host with
  # a distro rclone. The OS paths cover coreutils/grep and — importantly —
  # fusermount3, which comes from the distro's fuse3 package, not from nix.
  unitPath = lib.concatStringsSep ":" [
    "${config.home.profileDirectory}/bin"
    "${homeDirectory}/.local/bin"
    "/run/current-system/sw/bin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
  ];

  # One entry per mount. `path` is a subpath within the remote: empty mounts the
  # whole remote, which is right for Drive; the SMB backend exposes the server,
  # so caitsith needs the share name or the mount would be a directory
  # containing one directory.
  mounts = {
    gdrive = {
      path = "";
      description = "Google Drive";
    };
    caitsith = {
      path = "share";
      description = "caitsith (Batocera) SMB share";
    };
    # alisaie is the opposite case: 16 shares, and the account is meant to reach
    # all of /volume1, so the pathless mount that would be wrong for caitsith is
    # exactly right here — every share lands as a directory under ~/alisaie.
    # SMB rather than NFS is forced twice over: rclone has no nfs backend, and
    # DSM exports only four /volume1 paths to this subnet. See the header of
    # chezmoi/dot_local/bin/executable_rclone-mount for the measurements.
    alisaie = {
      path = "";
      description = "alisaie (Synology) SMB shares";
    };
  };

  mkService = name: {
    path,
    description,
  }: {
    Unit = {
      Description = "Mount ${description} at ~/${name} (rclone FUSE)";
      # Skip cleanly on a host where chezmoi has not applied the script yet.
      ConditionFileIsExecutable = mountScript;
      # A mount is only useful once there is a network to reach the remote over.
      # Advisory for a user unit (nothing here pulls the target in), but it
      # still orders the attempt after the network comes up at boot.
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      # Cap the Restart= loop below: three failures in an hour and it stops
      # trying until the next login.
      StartLimitIntervalSec = "1h";
      StartLimitBurst = 3;
    };

    Service = let
      args = "--remote ${name}" + lib.optionalString (path != "") " --path ${path}";
    in {
      Type = "simple";

      # THE "only if authenticated" GATE. ExecCondition is not ExecStartPre: a
      # non-zero exit makes systemd skip the unit and record it as succeeded,
      # where ExecStartPre would mark it failed. That difference is the whole
      # point — a host that has never configured this remote, or one whose
      # credential has expired, simply does not mount, with no failed unit and
      # no red in `systemctl --user status` to explain away at every login.
      # --check-auth calls `rclone about`, which is supported by both the drive
      # and smb backends and needs a live credential, so it fails on a revoked
      # or expired one rather than only on a missing remote.
      ExecCondition = "${mountScript} ${args} --check-auth";

      # Foreground: rclone mount holds the mount for as long as it runs, so the
      # process IS the mount and systemd can supervise it directly. Do not add
      # --daemon here; the unit would exit immediately and systemd would tear
      # down the mount it had just made.
      ExecStart = "${mountScript} ${args} --mountpoint ${homeDirectory}/${name}";
      ExecStop = "${mountScript} --remote ${name} --unmount --mountpoint ${homeDirectory}/${name}";

      Environment = ["PATH=${unitPath}"];

      # A dropped network, a resumed laptop, or a powered-off Batocera kills the
      # mount. Retry a few times, then stand down rather than reconnecting
      # forever.
      Restart = "on-failure";
      RestartSec = "30s";

      # A FUSE mount left behind by a killed rclone makes every stat of the path
      # return ENOTCONN, which is far more confusing than an absent mount. The
      # script clears a stale mount before remounting, and this makes sure the
      # process is gone first.
      KillMode = "mixed";
      TimeoutStopSec = "30s";
    };

    # default.target is the user session, so these come up at login — which is
    # also when an OAuth token is most likely to still be valid, since a desktop
    # login is when it would have been renewed by hand.
    Install.WantedBy = ["default.target"];
  };
in {
  # Linux only. There is no darwin counterpart: rclone mount on macOS needs
  # macFUSE, a kernel extension installed outside nix and gated behind a reboot
  # and a security prompt. Baking that into a login agent would fail on every
  # Mac that has not been through it, so mounts stay a Linux affordance and
  # darwin keeps gdrive-sync only.
  systemd.user.services =
    lib.mkIf pkgs.stdenv.isLinux
    (lib.mapAttrs' (n: v: lib.nameValuePair "rclone-mount-${n}" (mkService n v)) mounts);
}
