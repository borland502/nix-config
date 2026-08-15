# OpenSSH server, hardened, and the transport every other remote service on
# this host is expected to ride on.
#
# Nothing but 22 is opened to the network (see modules/desktop/krdp.nix): remote
# services are reached by forwarding over ssh, so ssh auth is the single front
# door instead of each service's own secret.
#
# The non-NixOS hosts get the same policy from
# chezmoi/run_onchange_provision-linux-host.sh.tmpl — keep the two in step.
{
  config,
  lib,
  ...
}: let
  user = "jhettenh";
  inherit (config.users.users.${user}.openssh) authorizedKeys;

  # Key-only auth is the goal, but turning passwords off before a key is
  # authorized just produces a host nobody can log into. Derive it instead: the
  # moment an authorized key is declared for the user, passwords switch off by
  # themselves. The remoting key below satisfies this, so the live value is
  # false — the fallback only matters if that key is ever withdrawn.
  haveAuthorizedKeys = authorizedKeys.keys != [] || authorizedKeys.keyFiles != [];
in {
  # The dedicated remoting keypair. Public half is tracked in the clear (it is
  # not a secret); the private half is sops-encrypted in
  # secrets/remoting-ssh.yaml and materialized to ~/.ssh/id_remoting by
  # home-manager/modules/sops.nix. keyFiles rather than keys so the literal
  # never has to be pasted into Nix and can never drift from the .pub.
  users.users.${user}.openssh.authorizedKeys.keyFiles = [
    ../../chezmoi/dot_config/ssh/remoting-key.pub
  ];

  services.openssh = {
    # openFirewall defaults to true, which is what puts 22 in
    # networking.firewall.allowedTCPPorts. Named here because the tunnel-only
    # policy depends on it.
    enable = true;
    openFirewall = true;

    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = !haveAuthorizedKeys;

      # UsePAM stays on (NixOS default) so account/session management still
      # applies; this only removes the interactive password prompt path, which
      # is otherwise a second way in behind PasswordAuthentication's back.
      KbdInteractiveAuthentication = false;

      # Required, not incidental: port forwarding is how KRdp and anything else
      # local-only is reached. Asserted explicitly so a future default flip
      # cannot silently sever that path.
      AllowTcpForwarding = "yes";

      # Nothing here needs to re-export a forwarded port to the wider network,
      # which would defeat the point of not opening service ports at all.
      GatewayPorts = "no";

      AllowAgentForwarding = "no";
      X11Forwarding = false;

      MaxAuthTries = 3;
      LoginGraceTime = 30;
    };
  };

  warnings = lib.optional (!haveAuthorizedKeys) ''
    sshd on this host still accepts password authentication: no authorized key
    is declared for ${user}. Add one to
    users.users.${user}.openssh.authorizedKeys.keys and passwords turn
    themselves off (modules/services/sshd.nix).
  '';
}
