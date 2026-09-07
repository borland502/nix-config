"""Monokai palette and the setvtrgb(8) generator for the Linux console.

The wall panel runs on a Linux VT, whose 16 colour slots are whatever the
console was left with. `--print-vtrgb` emits a palette in setvtrgb's format so
those 16 slots *are* Monokai; the systemd unit applies the result with a
non-fatal `ExecStartPre=-/usr/bin/setvtrgb /etc/vtrgb-monokai`.

With that palette loaded, rich's named colours (`bright_cyan`, `yellow`, ...)
resolve to the right Monokai hues on the console, which is why the renderer can
use names rather than carrying its own truecolor escapes.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

_FALLBACK_PALETTE = {
    "base00": "#222222", "base01": "#363537", "base02": "#525053",
    "base03": "#69676c", "base04": "#8b888f", "base05": "#bab6c0",
    "base06": "#fbf8ff", "base07": "#f7f1ff", "base08": "#FC618D",
    "base09": "#fd9353", "base0A": "#FCE566", "base0B": "#7BD88F",
    "base0C": "#5AD4E6", "base0D": "#948ae3", "base0E": "#fc618d",
    "base0F": "#fef20a", "base10": "#191919",
}  # fmt: skip

_PALETTE_CANDIDATES = (
    Path.home() / ".config/colors/monokai.toml",
    Path("/etc/colors/monokai.toml"),
)

# setvtrgb slot order: 0-7 normal, 8-15 bright. Keys beyond the fallback set
# (base12..base16) come from a deployed palette file; without one they fall back
# to base05, which is why a deployed monokai.toml gives a better console.
_VTRGB_ORDER = (
    "base00", "base08", "base0B", "base0A", "base0D", "base0E", "base0C", "base05",
    "base03", "base12", "base14", "base13", "base16", "base0E", "base15", "base07",
)  # fmt: skip


def load_palette() -> dict[str, str]:
    """Prefer a deployed palette so a scheme edit reaches the panel."""
    for candidate in _PALETTE_CANDIDATES:
        try:
            with candidate.open("rb") as fh:
                pal = tomllib.load(fh).get("palette", {})
        except (OSError, tomllib.TOMLDecodeError):
            continue
        if pal:
            return {**_FALLBACK_PALETTE, **pal}
    return dict(_FALLBACK_PALETTE)


def rgb(hexstr: str) -> tuple[int, int, int]:
    """Split ``#rrggbb`` into its three channel values."""
    h = hexstr.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def vtrgb_palette() -> str:
    """Emit a setvtrgb(8) palette so the console's 16 slots ARE Monokai.

    setvtrgb wants three comma-separated lines — all reds, all greens, all
    blues — one value per colour slot.
    """
    pal = load_palette()
    cols = [rgb(pal.get(k, pal["base05"])) for k in _VTRGB_ORDER]
    return "\n".join(",".join(str(c[i]) for c in cols) for i in range(3)) + "\n"
