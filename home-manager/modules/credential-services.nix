{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (config.home) homeDirectory;
  xdgBinHome = "${homeDirectory}/.local/bin";
  xdgCacheHome = "${homeDirectory}/.cache";
  # launchd has no failure-notification of its own, and the Kion agents are
  # otherwise mute: the log is the only signal, and nobody reads a log until
  # AWS access breaks. An expired App API key went unnoticed for a week that
  # way. The CMS SOP raises a desktop notification for the same reason.
  # Best-effort on purpose — a missing or refusing osascript must never turn a
  # credential failure into a launchd crash loop, hence the `|| true`.
  notifyKionFailure = message: ''
    [ -x /usr/bin/osascript ] && /usr/bin/osascript \
      -e 'display notification "${message}" with title "Kion credentials"' \
      >/dev/null 2>&1 || true
  '';
in {
  launchd.agents = {
    kion-aws-refresh = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        # kion-aws-refresh is deployed by chezmoi, not by nix, so on a host that
        # has not applied dotfiles yet this path does not exist and python would
        # fail every four hours forever. launchd has no ConditionFileIsExecutable
        # equivalent, so the guard has to be in the invocation: stand down quietly
        # until the script is there. Same intent as the systemd units' condition.
        #
        # The notify tail exists because these agents fail *silently*: an expired
        # App API key took a week to notice, during which every four-hour run
        # logged a failure nobody read. The CMS SOP raises a desktop notification
        # for the same reason.
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            [ -x "${xdgBinHome}/kion-aws-refresh" ] || exit 0
            "${pkgs.python3}/bin/python3" "${xdgBinHome}/kion-aws-refresh" && exit 0
            ${notifyKionFailure "AWS credential refresh failed - check the App API key"}
            exit 1
          ''
        ];
        # Kion issues a four-hour session (the API returns duration = 14400),
        # so refreshing every 14400s left exactly zero margin: each run landed
        # as the previous session died, and any drift — a late run, a sleeping
        # laptop, a slow call — put expired credentials on disk. Halving the
        # interval keeps a valid session in ~/.aws/credentials continuously
        # instead of instantaneously. `kac ensure` still refreshes on demand for
        # shells; this is what non-shell consumers depend on.
        StartInterval = 7200;
        StandardOutPath = "${xdgCacheHome}/kion-aws-refresh.log";
        StandardErrorPath = "${xdgCacheHome}/kion-aws-refresh.log";
      };
    };

    # Rotation of the long-lived Kion App API key. The key expires on an absolute
    # clock of roughly seven days measured from issuance — not, as the CMS SOP
    # states, after seven days of *inactivity*: an observed key died at 6d15h
    # while kion-aws-refresh used it successfully every four hours throughout.
    # Rotation therefore has to beat that clock unconditionally, and one missed
    # run is fatal rather than merely late, because rotation authenticates with
    # the very key it replaces and cannot self-heal once that key is dead.
    #
    # This supersedes a hand-installed LaunchAgent that macOS had begun killing
    # outright with OS_REASON_CODESIGNING. That plist reached python through the
    # Nix *profile symlink*, whose store target moves on every generation, which
    # invalidates the Lightweight Code Requirement launchd recorded for the job.
    # Pinning ${pkgs.python3} by absolute store path — as the refresher above
    # already does — is precisely what makes this agent immune to that.
    #
    # StartCalendarInterval, not StartInterval: launchd counts an interval from
    # *load*, so under RunAtLoad = false a reboot inside the window restarts the
    # clock and a long-interval job can starve indefinitely (the observed
    # failure: runs = 0 across four days of uptime). A calendar rule instead
    # fires once at the next wake after a missed occurrence, which is the launchd
    # equivalent of the Persistent = true already set on the Linux timers below.
    # Daily is deliberately tighter than the SOP's every-two-days: it is the
    # simplest calendar rule that expresses "catch up after any gap", rotation is
    # idempotent and costs one API call, and it leaves six days of slack against
    # the seven-day expiry instead of five.
    kion-api-key-rotate = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            [ -x "${xdgBinHome}/kion-api-key-rotate" ] || exit 0
            "${pkgs.python3}/bin/python3" "${xdgBinHome}/kion-api-key-rotate" && exit 0
            ${notifyKionFailure "App API key rotation failed - re-mint the key in Kion"}
            exit 1
          ''
        ];
        RunAtLoad = true;
        StartCalendarInterval = [
          {
            Hour = 12;
            Minute = 0;
          }
        ];
        StandardOutPath = "${xdgCacheHome}/kion-api-key-rotate.log";
        StandardErrorPath = "${xdgCacheHome}/kion-api-key-rotate.log";
      };
    };
  };
}
