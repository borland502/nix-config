"""Value formatting shared by the panels."""

from __future__ import annotations

from datetime import UTC, datetime

# Debian console fonts ship U+2588 and the box-drawing set but NOT the
# 1/8-block ramp U+2581..2587 — none of the ~200 fonts on a stock DietPi image
# has it. On such a terminal those cells render as garbage, so a coarser ramp
# built only from glyphs the console font maps is used instead.
SPARK_FINE = "▁▂▃▄▅▆▇█"
SPARK_COARSE = "·░▒█"

_MILLION = 1_000_000
_THOUSANDS_CUTOFF = 10_000


def sparkline(values: list[int], width: int, ramp: str = SPARK_FINE) -> str:
    """Render ``values`` as a single-line bar chart no wider than ``width``."""
    if not values:
        return ""
    vals = values[-width:] if len(values) > width else values
    peak = max(vals) or 1
    steps = len(ramp) - 1
    return "".join(ramp[min(steps, int(v / peak * steps))] for v in vals)


def human(n: object) -> str:
    """Abbreviate a count for a fixed-width tile, or ``-`` if it is not a number.

    Accepts ``object`` because the values come straight out of decoded JSON,
    where a missing key yields ``None`` and a malformed one can yield anything.
    """
    if not isinstance(n, (int, float, str)):
        return "-"
    try:
        value = int(n)
    except (TypeError, ValueError):
        return "-"
    if value >= _MILLION:
        return f"{value / _MILLION:.1f}M"
    if value >= _THOUSANDS_CUTOFF:
        return f"{value / 1000:.1f}k"
    return f"{value:,}"


def local_hms(iso: str) -> str:
    """Convert a UTC ISO-8601 timestamp to a local ``HH:MM:SS`` clock.

    Technitium emits UTC; the panel clock is local. Slicing the string instead
    leaves the feed 4-5 hours off the header clock, which reads as a stall.
    .NET also emits 7-digit fractional seconds, which ``fromisoformat`` rejects,
    so the fraction is trimmed to microseconds first.
    """
    if not iso:
        return "--:--:--"
    text = iso.strip().replace("Z", "+00:00")
    if "." in text:
        head, _, tail = text.partition(".")
        digits = ""
        rest = ""
        for i, ch in enumerate(tail):
            if ch.isdigit():
                digits += ch
            else:
                rest = tail[i:]
                break
        text = f"{head}.{digits[:6]}{rest}"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return iso[11:19] or "--:--:--"
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone().strftime("%H:%M:%S")
