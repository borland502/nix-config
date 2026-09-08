{
  config,
  lib,
  pkgs,
  ...
}: let
  homeDirectory = config.home.homeDirectory;

  # chezmoi deploys the script, not nix, so this is a plain path and the units
  # guard on its existence. Same arrangement as gdrive-sync.nix.
  snapshotScript = "${homeDirectory}/.local/bin/keepass-snapshot";

  mkPath = extra:
    lib.concatStringsSep ":" ([
        "${config.home.profileDirectory}/bin"
        "${homeDirectory}/.local/bin"
        "/run/current-system/sw/bin"
      ]
      ++ extra);

  linuxPath = mkPath ["/usr/local/bin" "/usr/bin" "/bin"];
  darwinPath = mkPath ["/opt/homebrew/bin" "/usr/local/bin" "/usr/bin" "/bin" "/usr/sbin" "/sbin"];

  logFile = "${config.xdg.cacheHome}/keepass-snapshot.launchd.log";
in {
  # Dated snapshots of the KeePass vault. Deliberately a separate unit from
  # gdrive-sync rather than another pass inside it: the vault is the one piece of
  # state here with no other copy, and folding it in would make it hostage to a
  # full dotfiles backup succeeding. That is not hypothetical — gdrive-sync has
  # been failing on darwin since 2026-08-14 on an expired token, and a vault
  # snapshot must not inherit that.
  #
  # Scheduled on BOTH platforms, even though only tifa can currently reach the
  # remote, because the script exits 0 and silent on a host with no usable
  # gdrive remote. Whichever host is awake takes the snapshot; a same-day
  # second run just overwrites the same dated object, so the two never conflict.

  # ── Linux: systemd user timer ───────────────────────────────────────────────
  systemd.user = lib.mkIf pkgs.stdenv.isLinux {
    services.keepass-snapshot = {
      Unit = {
        Description = "Dated snapshot of the KeePass vault on Google Drive";
        ConditionFileIsExecutable = snapshotScript;
        After = ["network-online.target"];
        Wants = ["network-online.target"];
        StartLimitIntervalSec = "6h";
        StartLimitBurst = 3;
      };

      Service = {
        Type = "oneshot";
        ExecStart = snapshotScript;
        Environment = ["PATH=${linuxPath}"];
        # Server-side copy, so this is a couple of API calls rather than a
        # transfer; it still has no business competing with interactive use.
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "30m";
        Restart = "on-failure";
        RestartSec = "10min";
      };
    };

    timers.keepass-snapshot = {
      Unit.Description = "Weekly KeePass vault snapshot";

      Timer = {
        # Weekly, and Persistent so a week missed with the machine off fires at
        # the next opportunity instead of being skipped. Persistent only works
        # with OnCalendar= — do not swap this for OnUnitActiveSec=1w.
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
        AccuracySec = "5m";
      };

      Install.WantedBy = ["timers.target"];
    };
  };

  # ── darwin: launchd agent ───────────────────────────────────────────────────
  # launchd has no Persistent= equivalent, and unlike gdrive-sync there is no
  # --if-stale gate to lean on. StartCalendarInterval with Weekday fires weekly
  # and replays an interval missed while the Mac was asleep; one missed while it
  # was powered off is simply dropped. That is acceptable here in a way it was
  # not for the daily backup: snapshots are cheap and idempotent per date, and
  # the Linux timer covers the same vault.
  launchd.agents.keepass-snapshot = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [snapshotScript];
      EnvironmentVariables.PATH = darwinPath;

      StartCalendarInterval = [
        {
          Weekday = 0; # Sunday
          Hour = 3;
          Minute = 17;
        }
      ];

      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;

      StandardOutPath = logFile;
      StandardErrorPath = logFile;
    };
  };
}
