# Wake-on-LAN: arm the wired NIC to power the machine back on when it receives a
# magic packet addressed to its MAC.
#
# Driven through NetworkManager rather than a per-interface ethtool unit. The
# NixOS option for this is networking.interfaces.<name>.wakeOnLan.enable, which
# needs an interface name; this host's wired NIC comes and goes with a
# Thunderbolt dock (see the enp0s13f0u1u2u1 in hardware-configuration.nix), so a
# name written down here is a name that will be wrong. A NetworkManager
# connection default matches on device *type* instead and covers whatever wired
# NIC is present, including one that first appears after this was written.
#
# NetworkManager applies the setting when it activates a connection, which is
# also what re-arms it on every boot. Nothing clears it at shutdown —
# connection.down-on-poweroff is off by default — so the flag is still set in
# the NIC when the machine reaches S5, which is the whole point.
#
# The non-NixOS hosts get the same policy, in the same shape, from
# chezmoi/run_onchange_provision-linux-host.sh.tmpl — keep the two in step.
#
# Firmware still has the last word, and it cannot be configured from here: a
# board with "Wake on PCIe/LAN" disabled, or ErP/Deep Sleep enabled, cuts NIC
# power at S5 and no amount of driver state survives that. If a host answers
# `wake` from suspend but not from a full power-off, that is the setting to go
# looking for, not this file.
#
# Sending side: the `wake` helper, driven from the `mac` key in
# secrets/hosts.toml (SOPS-encrypted; decrypted to ~/.config/ssh/hosts.toml).
{
  networking.networkmanager.settings = {
    # Sections named connection* are NetworkManager's "connection defaults":
    # match-device selects the devices, the remaining keys supply property
    # defaults for any profile that has not set them itself. This leaves the
    # connection profiles alone, so a wired NIC that NetworkManager auto-creates
    # a profile for is covered without anything being written down about it.
    #
    # Wired only. WoWLAN is a separate feature with its own flags, and a
    # sleeping wifi card that has dropped its association has nothing to receive
    # the packet on — pretending otherwise would just produce a host that never
    # wakes and no indication why.
    connection-wake-on-lan = {
      match-device = "type:ethernet";
      "ethernet.wake-on-lan" = "magic";
    };
  };
}
