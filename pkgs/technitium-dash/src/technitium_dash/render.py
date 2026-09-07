"""Panel rendering.

Presentation is delegated to rich rather than hand-built ANSI. That removes
three things the original had to carry itself: truecolor/256-colour/no-colour
downgrade, correct cell-width measurement (the previous regex-stripping
`vlen` mis-measured double-width and combining characters), and flicker-free
repainting over SSH.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING
from urllib.parse import urlparse

from rich.align import Align
from rich.console import Group, RenderableType
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from .format import SPARK_COARSE, SPARK_FINE, human, local_hms, sparkline

if TYPE_CHECKING:
    from .api import JsonDict

PALETTE = {
    "accent": "bright_cyan",
    "alert": "bright_red",
    "warn": "yellow",
    "orange": "dark_orange",
    "purple": "medium_purple",
    "ok": "green",
    "muted": "grey50",
    "label": "grey70",
}


def _tiles(stats: JsonDict) -> Table:
    total = int(stats.get("totalQueries", 0) or 0)
    blocked = int(stats.get("totalBlocked", 0) or 0)
    failures = int(stats.get("totalServerFailure", 0) or 0)
    pct = (blocked / total * 100) if total else 0.0

    cells = [
        ("QUERIES", human(total), PALETTE["accent"]),
        ("BLOCKED", f"{human(blocked)} {pct:.0f}%", PALETTE["alert"]),
        ("CACHED", human(stats.get("totalCached")), PALETTE["warn"]),
        ("RECURSIVE", human(stats.get("totalRecursive")), PALETTE["orange"]),
        ("NXDOMAIN", human(stats.get("totalNxDomain")), PALETTE["warn"]),
        ("CLIENTS", human(stats.get("totalClients")), PALETTE["purple"]),
        ("FAILURES", human(failures), PALETTE["ok"] if not failures else PALETTE["alert"]),
    ]

    table = Table.grid(expand=True, padding=(0, 1))
    for _ in cells:
        table.add_column(justify="center", ratio=1)
    table.add_row(*[Text(value, style=f"bold {colour}") for _, value, colour in cells])
    table.add_row(*[Text(label, style=PALETTE["label"]) for label, _, _ in cells])
    return table


def _chart(chart: JsonDict, width: int, *, coarse: bool) -> RenderableType | None:
    series = {d.get("label"): d.get("data", []) for d in (chart.get("datasets") or [])}
    labels = chart.get("labels") or []
    inner = max(20, width - 18)
    if not series.get("Total"):
        return None

    total = [int(x or 0) for x in series["Total"]]
    blocked = [int(x or 0) for x in series.get("Blocked", [])]
    ramp = SPARK_COARSE if coarse else SPARK_FINE
    rows = Table.grid(padding=(0, 2))
    rows.add_column(style=PALETTE["label"], no_wrap=True)
    rows.add_column(no_wrap=True)
    rows.add_row("queries/min", Text(sparkline(total, inner, ramp), style=PALETTE["accent"]))
    if blocked:
        rows.add_row("blocked/min", Text(sparkline(blocked, inner, ramp), style=PALETTE["alert"]))
    if labels:
        span = f"{labels[0]} → {labels[-1]}   peak {max(total)}/min"
        rows.add_row("", Text(span, style=PALETTE["muted"]))
    return rows


def _top_column(title: str, rows: list[JsonDict] | None, colour: str, n: int) -> Table:
    table = Table.grid(expand=True, padding=(0, 1))
    table.add_column(ratio=1, overflow="ellipsis", no_wrap=True)
    table.add_column(justify="right", width=7, no_wrap=True)
    table.add_row(Text(title, style=f"bold {colour}"), "")
    for entry in (rows or [])[:n]:
        table.add_row(
            Text(str(entry.get("name", "?"))),
            Text(human(entry.get("hits")), style=PALETTE["muted"]),
        )
    return table


def _feed(queries: list[JsonDict], limit: int) -> Table:
    table = Table.grid(expand=True, padding=(0, 1))
    table.add_column(width=8, no_wrap=True, style=PALETTE["muted"])
    table.add_column(width=15, no_wrap=True, overflow="ellipsis")
    table.add_column(ratio=1, no_wrap=True, overflow="ellipsis")
    table.add_column(width=10, no_wrap=True, justify="right")
    for q in queries[:limit]:
        response = str(q.get("responseType") or "")
        style = PALETTE["alert"] if response.lower() == "blocked" else PALETTE["label"]
        table.add_row(
            local_hms(str(q.get("timestamp") or "")),
            str(q.get("clientIpAddress") or "?"),
            str(q.get("qname") or "?").rstrip("."),
            Text(response or "-", style=style),
        )
    return table


@dataclass(frozen=True, slots=True)
class Frame:
    """Everything one rendered panel needs.

    Collected into a single object rather than eleven keyword arguments: the
    caller assembles it once per refresh, and adding a panel does not change
    every call site.
    """

    url: str
    name: str
    version: str
    stats: JsonDict
    chart: JsonDict
    tops: JsonDict
    queries: list[JsonDict]
    width: int
    error: str | None
    interval: int
    clock: str
    # How many feed rows to draw. Derived from the console height by the caller
    # rather than fixed: the wall panel is 1080p / 36 rows, where a hardcoded 12
    # left a third of the screen empty.
    feed_rows: int = 12
    # True on the tty1 wall panel: a Linux VT with a console font. rich reports
    # `standard`/None there, and the caller maps that to this flag.
    #
    # It exists for exactly one reason: the 1/8-block sparkline ramp
    # U+2581..2587 is NOT in the console font, so the fine ramp renders as
    # garbage and the coarse one must be used instead.
    #
    # Verified 2026-09-07 against the font the unit loads, by dumping its
    # Unicode map (`zcat Uni2-DejaVu30x16.psf.gz | psfgettable -`):
    #   U+2581 ABSENT  <- the whole reason this flag exists
    #   U+00B7 U+2591 U+2592 U+2588 PRESENT   (coarse ramp)
    #   U+2026 U+2192 U+2500 U+250C U+256D PRESENT
    # So ellipsis truncation, the -> arrow, and rich's rounded panel corners are
    # all safe here; do not "fix" them without re-running that check.
    limited_console: bool = False


def build(frame: Frame) -> RenderableType:
    """Compose the full panel for one refresh."""
    url = frame.url
    name = frame.name
    version = frame.version
    stats = frame.stats
    chart = frame.chart
    tops = frame.tops
    queries = frame.queries
    width = frame.width
    error = frame.error
    interval = frame.interval
    clock = frame.clock

    host = urlparse(url).hostname or url

    header = Table.grid(expand=True)
    header.add_column(justify="left")
    header.add_column(justify="right")
    header.add_row(
        Text.assemble(
            ("TECHNITIUM ", f"bold {PALETTE['accent']}"),
            (f"{name} ", "default"),
            (f"v{version}", PALETTE["muted"]),
        ),
        Text(f"{host}  {clock}", style=PALETTE["muted"]),
    )

    blocks: list[RenderableType] = [header, _tiles(stats or {})]

    if error:
        blocks.append(
            Text.assemble(
                ("⚠ ", f"bold {PALETTE['alert']}"),
                (error, f"bold {PALETTE['alert']}"),
                (f"  — retrying every {interval}s, last known values shown", PALETTE["muted"]),
            )
        )

    chart_rows = _chart(chart or {}, width, coarse=frame.limited_console)
    if chart_rows is not None:
        blocks.append(chart_rows)

    tops = tops or {}
    columns = Table.grid(expand=True, padding=(0, 2))
    columns.add_column(ratio=1)
    columns.add_column(ratio=1)
    columns.add_column(ratio=1)
    columns.add_row(
        _top_column("TOP DOMAINS", tops.get("topDomains"), PALETTE["accent"], 6),
        _top_column("TOP BLOCKED", tops.get("topBlockedDomains"), PALETTE["alert"], 6),
        _top_column("TOP CLIENTS", tops.get("topClients"), PALETTE["purple"], 6),
    )
    blocks.append(columns)

    if queries:
        blocks.append(
            Panel(
                _feed(queries, frame.feed_rows),
                title="live queries",
                border_style=PALETTE["muted"],
            ),
        )

    return Align.left(Group(*blocks))
