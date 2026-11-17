# Graphical sudo authentication on Linux

Home Manager supplies a default `SUDO_ASKPASS` for Linux sessions. The dispatcher
chooses a desktop password dialog from trusted absolute paths and passes its
output directly to sudo. It prefers the host ksshaskpass, then a pinned Nix
package and known system alternatives; it does not search `PATH`. A pre-existing
`SUDO_ASKPASS` takes precedence. Generic Linux provisioning installs the host
package.

For commands issued by an agent, use `sudo -A <command>` to request the dialog
explicitly, including when the agent has a pseudo-terminal. For a direct shell
action in the agent, use `! sudo -A <command>`. Native sudo can also use askpass
when it has no controlling terminal and detects a graphical display. Older sudo
versions may not detect a Wayland-only display for this automatic fallback;
`-A` explicitly requests the dialog there too. Normal sudo credentials caching
still applies, and `sudo -n` fails instead of prompting when authentication is
needed.

The session must have `DISPLAY` or `WAYLAND_DISPLAY` and an available desktop
helper; headless sessions cannot show a dialog. Applications inherit their
starting environment, so restart the desktop session or agent after activation
if it does not inherit the new variable and display settings. Agent sandbox and
permission restrictions still apply and may prevent sudo or the dialog from
running.

After activating on a Linux desktop, a harmless validation is `sudo -A true`.
If authentication is cached, it may finish without a dialog. To check
cancellation, use a fresh authentication context, run the same command, and
cancel the dialog; sudo should fail without executing the command. Do not share
or record the password. A live desktop dialog has not yet been validated as
part of this change.
