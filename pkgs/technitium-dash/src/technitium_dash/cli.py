"""Command line entry point and refresh loop."""

from __future__ import annotations

import argparse
import signal
import sys
import time

from rich.console import Console
from rich.live import Live

from . import __version__, render
from .api import ApiError, JsonDict, Technitium
from .config import DEFAULT_MAX_PER_NAME, Config, load_config
from .palette import vtrgb_palette

_REFRESH_TICKS_PER_SECOND = 4

# Rows the panel spends on everything except the live feed: header (1),
# stat tiles (2), the per-minute chart (3), the top-N columns (7), the feed
# panel's own border (2), plus a row of slack so a resize cannot clip it.
_CHROME_ROWS = 16
_MIN_FEED_ROWS = 6


def _feed_rows_for(height: int) -> int:
    """How many live-feed rows fit in a console of ``height`` rows."""
    return max(_MIN_FEED_ROWS, height - _CHROME_ROWS)


def build_parser() -> argparse.ArgumentParser:
    """Construct the argument parser."""
    p = argparse.ArgumentParser(
        prog="technitium-dash",
        description="Technitium DNS stats + live query panel",
    )
    p.add_argument("--url", help="API base, e.g. http://dns.example.lan:5380/api")
    p.add_argument("--token", help="API token")
    p.add_argument("--fallback", help="secondary API base used if the primary fails")
    p.add_argument("--fallback-token", help="token for --fallback (defaults to --token)")
    p.add_argument(
        "--exclude",
        action="append",
        metavar="NAME",
        help="hide a query name from the live feed, with everything under it "
        "(repeatable, or comma-separated). Use for a host that polls in a tight "
        "loop and would otherwise fill the panel. Stats and top-domain columns "
        "still count it.",
    )
    p.add_argument(
        "--max-per-name",
        metavar="N",
        help="show at most N rows for any one query name "
        f"(default {DEFAULT_MAX_PER_NAME}, 0 disables the cap). Keeps a single "
        "busy name from crowding out the feed without hiding it entirely.",
    )
    p.add_argument("--interval", type=int, default=5, help="refresh seconds (default 5)")
    p.add_argument(
        "--window",
        default="LastHour",
        choices=["LastHour", "LastDay", "LastWeek", "LastMonth"],
    )
    p.add_argument("--once", action="store_true", help="render one frame and exit")
    p.add_argument(
        "--print-vtrgb",
        action="store_true",
        help="print a setvtrgb(8) Monokai palette and exit; the console has only "
        "16 colour slots, and this makes them the right hues. Redirect to "
        "/etc/vtrgb-monokai, which the systemd unit applies at start.",
    )
    p.add_argument("--version", action="version", version=f"technitium-dash {__version__}")
    return p


class Poller:
    """Polls the configured servers and remembers the last good response.

    Holds the cross-refresh state — last known values, discovered version, and
    which server is currently answering — so a failed refresh can keep showing
    the previous numbers instead of blanking the panel.
    """

    def __init__(self, servers: list[Technitium], window: str, feed_rows: int = 12) -> None:
        """Poll ``servers`` in order, falling back to later ones on failure."""
        self._feed_rows = feed_rows
        self._servers = servers
        self._window = window
        self._stats: JsonDict = {}
        self._chart: JsonDict = {}
        self._tops: JsonDict = {}
        self._queries: list[JsonDict] = []
        self._version = "?"
        self._active = 0

    def close(self) -> None:
        """Close every client."""
        for srv in self._servers:
            srv.close()

    def _refresh_from(self, srv: Technitium) -> None:
        stats = srv.stats(self._window)
        if self._version == "?":
            self._version = srv.version()
        self._stats = stats.get("stats", stats)
        self._chart = stats.get("mainChartData", {}) or {}
        self._tops = stats
        try:
            self._queries = srv.queries(self._feed_rows)
        except ApiError:
            # The Sqlite query-log app is optional: no feed is not an outage,
            # so keep the stats panel rather than erroring out.
            self._queries = []

    def poll(self) -> str | None:
        """Refresh from the first server that answers; return an error if none do."""
        error: str | None = None
        for offset in range(len(self._servers)):
            idx = (self._active + offset) % len(self._servers)
            srv = self._servers[idx]
            try:
                self._refresh_from(srv)
            except ApiError as exc:
                error = f"{srv.url}: {exc}"
                continue
            self._active = idx
            return None
        return error

    def frame(
        self,
        *,
        width: int,
        interval: int,
        error: str | None,
        limited_console: bool = False,
        feed_rows: int = 12,
    ) -> render.Frame:
        """Package the last known values for rendering."""
        return render.Frame(
            url=self._servers[self._active].url,
            # Label the pane by role, not URL — the host already shows on the
            # right of the header, and repeating it there read as a bug.
            name="primary" if self._active == 0 else "fallback",
            version=self._version,
            stats=self._stats,
            chart=self._chart,
            tops=self._tops,
            queries=self._queries,
            width=width,
            error=error,
            interval=interval,
            clock=time.strftime("%H:%M:%S"),
            limited_console=limited_console,
            feed_rows=feed_rows,
        )


def _build_servers(cfg: Config) -> list[Technitium]:
    """Build the primary client, plus the fallback when one is configured."""
    servers = [
        Technitium(cfg.url, cfg.token, exclude=cfg.exclude, max_per_name=cfg.max_per_name),
    ]
    if cfg.fallback:
        servers.append(
            Technitium(
                cfg.fallback,
                cfg.fallback_token or cfg.token,
                exclude=cfg.exclude,
                max_per_name=cfg.max_per_name,
            ),
        )
    return servers


def main() -> int:
    """Run the panel until interrupted, or render a single frame with --once."""
    args = build_parser().parse_args()

    # Before load_config: this needs no server, and demanding a token to print a
    # palette would make bootstrapping the console a chicken-and-egg problem.
    if args.print_vtrgb:
        sys.stdout.write(vtrgb_palette())
        return 0

    cfg = load_config(args)

    console = Console()
    feed_rows = _feed_rows_for(console.height)
    poller = Poller(_build_servers(cfg), args.window, feed_rows=feed_rows)
    stopped = False

    def _stop(*_: object) -> None:
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    # A Linux VT reports `standard` (8/16 colour) or nothing at all — that is
    # the wall-panel case, where the console font also lacks the fine block ramp
    # and rich's rounded panel corners.
    limited_console = console.color_system in (None, "standard")

    def next_frame() -> render.Frame:
        error = poller.poll()
        return poller.frame(
            width=console.width,
            interval=args.interval,
            error=error,
            limited_console=limited_console,
            feed_rows=feed_rows,
        )

    try:
        if args.once:
            console.print(render.build(next_frame()))
            return 0
        # screen=True gives the alternate screen and hides the cursor, which the
        # previous implementation drove with raw escape codes.
        with Live(
            render.build(next_frame()),
            console=console,
            screen=True,
            refresh_per_second=_REFRESH_TICKS_PER_SECOND,
        ) as live:
            while not stopped:
                for _ in range(args.interval * _REFRESH_TICKS_PER_SECOND):
                    if stopped:
                        break
                    time.sleep(1 / _REFRESH_TICKS_PER_SECOND)
                if stopped:
                    break
                live.update(render.build(next_frame()))
    finally:
        poller.close()
    return 0
