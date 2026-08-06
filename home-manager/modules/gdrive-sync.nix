{
  config,
  lib,
  pkgs,
  ...
}: let
  homeDirectory = config.home.homeDirectory;

  # chezmoi deploys the script (chezmoi/dot_local/bin/executable_sync-to-gdrive),
  # not nix — so this is a plain path, not a store path, and the units guard on
  # its existence rather than assuming it.
  syncScript = "${homeDirectory}/.local/bin/sync-to-gdrive";

  # Neither systemd user units nor launchd agents inherit the login shell's
  # environment, and the script's `#!/usr/bin/env zsh` needs a PATH to resolve
  # zsh through. Nix profile first: rclone and zsh both come from there
  # (common.nix), so the scheduled job uses the same versions as an interactive
  # run even on a host that also has a distro or Homebrew rclone. The OS paths
  # stay as a fallback and cover the coreutils/grep the script calls.
  mkPath = extra:
    lib.concatStringsSep ":" ([
        "${config.home.profileDirectory}/bin"
        "${homeDirectory}/.local/bin"
        "/run/current-system/sw/bin"
      ]
      ++ extra);

  linuxPath = mkPath ["/usr/local/bin" "/usr/bin" "/bin"];
  darwinPath = mkPath ["/opt/homebrew/bin" "/usr/local/bin" "/usr/bin" "/bin" "/usr/sbin" "/sbin"];

  logFile = "${config.xdg.cacheHome}/gdrive-sync.launchd.log";
in {
  # ── Linux: systemd user timer ───────────────────────────────────────────────
  systemd.user = lib.mkIf pkgs.stdenv.isLinux {
    services.gdrive-sync = {
      Unit = {
        Description = "Back up ~/.config and ~/.local to Google Drive (rclone)";
        # Skip cleanly (rather than fail) on a host where chezmoi has not
        # applied the script yet.
        ConditionFileIsExecutable = syncScript;
        # A laptop resuming without network, or an expired rclone token, fails
        # the run. Retry a couple of times, then stand down until the next timer
        # fire instead of hammering every 15 min all day.
        StartLimitIntervalSec = "2h";
        StartLimitBurst = 3;
      };

      Service = {
        Type = "oneshot";
        # No --if-stale here: Persistent= below is a real catch-up guarantee, so
        # systemd never fires a run that a stamp check would need to suppress.
        ExecStart = syncScript;
        Environment = ["PATH=${linuxPath}"];
        # Background work: never contend with interactive use. The full backup
        # pass can run long on a first sync, so allow well past the default 90s.
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "6h";
        Restart = "on-failure";
        RestartSec = "15min";
      };
    };

    timers.gdrive-sync = {
      Unit.Description = "Daily Google Drive backup of ~/.config and ~/.local";

      Timer = {
        # Every 24h at midnight. Persistent=true records the last trigger under
        # ~/.local/share/systemd/timers, so a run missed while the laptop was
        # off (or logged out) fires at the next opportunity instead of being
        # skipped. Persistent only works with OnCalendar= — do not swap this for
        # OnUnitActiveSec=1d.
        OnCalendar = "daily";
        Persistent = true;
        # Catch-up runs would otherwise start the moment the session comes up,
        # right when the machine is busiest. Spread them over the first half
        # hour.
        RandomizedDelaySec = "30m";
        AccuracySec = "1m";
      };

      Install.WantedBy = ["timers.target"];
    };
  };

  # ── darwin: launchd agent ───────────────────────────────────────────────────
  # launchd has no equivalent of systemd's Persistent=. StartCalendarInterval
  # replays an interval missed while the Mac was ASLEEP (it fires on wake), but
  # an interval missed while the Mac was powered OFF is simply dropped —
  # launchd just schedules the next occurrence when the agent loads. So the
  # catch-up is built from two halves:
  #   * StartCalendarInterval gives the daily cadence and covers sleep.
  #   * RunAtLoad fires at every login/boot, which is the "next available
  #     opportunity" after the machine was off.
  # RunAtLoad alone would re-sync on every login, so the script is invoked with
  # --if-stale 24: it exits immediately unless the last successful backup is
  # more than 24h old. That check is also what keeps the two triggers from
  # doubling up.
  launchd.agents.gdrive-sync = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [syncScript "--if-stale" "24"];
      EnvironmentVariables.PATH = darwinPath;

      StartCalendarInterval = [
        {
          Hour = 0;
          Minute = 6;
        }
      ];
      RunAtLoad = true;

      # Background work, as with Nice/IOSchedulingClass on the Linux side.
      # ProcessType=Background is what actually opts the job into macOS's
      # throttled CPU/IO band; Nice and LowPriorityIO reinforce it.
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;

      # launchd has no journal — without these the output is discarded. The
      # script's own rclone log stays at ~/.cache/claude/rclone-gdrive.log.
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
    };
  };
}
