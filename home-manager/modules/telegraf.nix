# Telegraf host-metrics agent, as a systemd *user* service.
#
# Why a user service and not a system one: this host (tifa, CachyOS) is not in
# the flake — there is no NixOS `services.telegraf` to use, and its sudo wants a
# password, so an /etc unit would be another hand-applied change living only on
# disk. `loginctl show-user` reports Linger=yes here, so a user service starts
# at boot without anyone logging in, which is the only thing a system unit would
# have bought. Everything telegraf collects below (cpu, mem, disk, net, temp)
# reads from /proc and /sys and needs no privilege.
#
# The token is deliberately NOT in the rendered config: `xdg.configFile` writes
# into the Nix store, which is world-readable. It arrives instead through
# EnvironmentFile from the sops-materialized ~/.config/telegraf/influx.env
# (see modules/sops.nix), and telegraf expands ${INFLUX_TOKEN} at load time.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # The InfluxDB URL is NOT inlined here. nix-config is public and that is an
  # internal hostname -- `task check:secret-hygiene` rejects it in the clear, so
  # it travels with the token in secrets/telegraf.yaml and arrives as
  # ${INFLUX_URL} through the same EnvironmentFile. Org and bucket are generic
  # names and carry nothing sensitive, so they stay readable here.
  influxOrg = "proxmox";
  influxBucket = "telegraf";

  envFile = "${config.home.homeDirectory}/.config/telegraf/influx.env";

  telegrafConf = pkgs.writeText "telegraf.conf" ''
    [agent]
      interval = "30s"
      round_interval = true
      metric_batch_size = 1000
      metric_buffer_limit = 10000
      # Jitter so every host in the fleet does not flush on the same tick.
      collection_jitter = "5s"
      flush_interval = "30s"
      flush_jitter = "5s"
      omit_hostname = false

    [[outputs.influxdb_v2]]
      urls = ["''${INFLUX_URL}"]
      token = "''${INFLUX_TOKEN}"
      organization = "${influxOrg}"
      bucket = "${influxBucket}"

    [[inputs.cpu]]
      percpu = false
      totalcpu = true
      collect_cpu_time = false
      report_active = true

    [[inputs.mem]]
    [[inputs.swap]]
    [[inputs.system]]
    [[inputs.processes]]
    [[inputs.kernel]]

    [[inputs.disk]]
      # Without this a Nix host emits a row per /nix/store bind mount and per
      # squashfs, burying the real filesystems.
      ignore_fs = ["tmpfs", "devtmpfs", "devfs", "overlay", "aufs", "squashfs", "ramfs"]

    [[inputs.diskio]]
    [[inputs.net]]
    [[inputs.temp]]
  '';
in {
  home.packages = [pkgs.telegraf];

  systemd.user = lib.mkIf pkgs.stdenv.isLinux {
    services.telegraf = {
      Unit = {
        Description = "Telegraf host metrics agent (InfluxDB)";
        # Without the token file telegraf starts, fails to expand ${INFLUX_TOKEN}
        # under its strict env handling (default since 1.38) and crash-loops.
        # Skip cleanly instead until sops has materialized it.
        ConditionPathExists = envFile;
        # sops-nix.service is what materializes that env file, and home-manager
        # starts both units in the same activation. Without this ordering the
        # condition is evaluated before the secret exists and the unit is
        # SKIPPED, not failed -- so it looks like nothing happened at all and
        # nothing appears in the journal beyond "unmet condition check".
        After = ["network-online.target" "sops-nix.service"];
        Wants = ["network-online.target" "sops-nix.service"];
      };

      Service = {
        Type = "simple";
        EnvironmentFile = envFile;
        ExecStart = "${pkgs.telegraf}/bin/telegraf --config ${telegrafConf}";
        Restart = "on-failure";
        RestartSec = "30s";
        # Metrics collection must never compete with interactive work.
        Nice = 10;
      };

      Install.WantedBy = ["default.target"];
    };
  };
}
