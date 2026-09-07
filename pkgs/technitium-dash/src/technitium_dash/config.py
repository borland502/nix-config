"""Configuration resolution: flags, environment, then the TOML file."""

from __future__ import annotations

import os
import sys
import tomllib
from collections.abc import Iterable
from pathlib import Path
from typing import TYPE_CHECKING, NamedTuple

if TYPE_CHECKING:
    import argparse

DEFAULT_MAX_PER_NAME = 3
CONFIG_PATH = Path.home() / ".config/technitium-dash/config.toml"


class Config(NamedTuple):
    """Fully resolved settings for one run."""

    url: str
    token: str
    fallback: str | None
    fallback_token: str | None
    exclude: tuple[str, ...]
    max_per_name: int


def clean_names(values: object) -> tuple[str, ...]:
    """Normalise a list or comma/space separated string of DNS names.

    Accepts ``object`` because the value may arrive from argparse (list), the
    environment (comma/space separated string), or TOML (either).
    """
    if not values:
        return ()
    if isinstance(values, str):
        parts = values.replace(",", " ").split()
    elif isinstance(values, Iterable):
        parts = [str(v) for v in values]
    else:
        parts = [str(values)]
    return tuple(p.strip().rstrip(".").lower() for p in parts if p.strip())


def positive_int(value: object, source: str) -> int | None:
    """Parse a non-negative integer, exiting with a clear message if invalid."""
    if value is None or value == "":
        return None
    if not isinstance(value, (int, str)):
        sys.exit(f"technitium-dash: {source} must be an integer")
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        sys.exit(f"technitium-dash: {source} must be an integer")
    if parsed < 0:
        sys.exit(f"technitium-dash: {source} must not be negative")
    return parsed


def load_config(args: argparse.Namespace) -> Config:
    """Resolve settings from flags, then environment, then the TOML file."""
    url = args.url or os.environ.get("TECHNITIUM_URL")
    token = args.token or os.environ.get("TECHNITIUM_TOKEN")
    fallback = args.fallback
    fb_token = args.fallback_token or os.environ.get("TECHNITIUM_FALLBACK_TOKEN")
    exclude = clean_names(args.exclude) or clean_names(os.environ.get("TECHNITIUM_EXCLUDE"))
    cap = positive_int(args.max_per_name, "--max-per-name")
    if cap is None:
        cap = positive_int(os.environ.get("TECHNITIUM_MAX_PER_NAME"), "TECHNITIUM_MAX_PER_NAME")

    # The config is read for `exclude` and `max_per_name` even when url/token
    # came from elsewhere: how crowded the feed gets is a property of the
    # network, not of how this invocation was pointed at a server.
    if (not url or not token or not exclude or cap is None) and CONFIG_PATH.exists():
        try:
            with CONFIG_PATH.open("rb") as fh:
                cfg = tomllib.load(fh)
        except OSError as exc:
            sys.exit(f"technitium-dash: cannot read {CONFIG_PATH}: {exc}")
        except tomllib.TOMLDecodeError as exc:
            sys.exit(f"technitium-dash: invalid TOML in {CONFIG_PATH}: {exc}")
        url = url or cfg.get("url")
        token = token or cfg.get("token")
        fallback = fallback or cfg.get("fallback_url")
        fb_token = fb_token or cfg.get("fallback_token")
        exclude = exclude or clean_names(cfg.get("exclude"))
        if cap is None:
            cap = positive_int(cfg.get("max_per_name"), "max_per_name")

    if not url or not token:
        sys.exit(
            "technitium-dash: no server configured.\n"
            "  set TECHNITIUM_URL and TECHNITIUM_TOKEN, pass --url/--token,\n"
            f"  or create {CONFIG_PATH} with url/token keys."
        )

    # Each Technitium instance issues its own tokens; reusing the primary's
    # against the secondary yields a confusing auth error at the exact moment
    # the panel is meant to be useful. Default to it only as a convenience.
    return Config(
        url,
        token,
        fallback,
        fb_token or token,
        exclude,
        DEFAULT_MAX_PER_NAME if cap is None else cap,
    )
