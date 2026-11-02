"""Fail-open per-source parser cache; changed files replay full call state."""

from dataclasses import asdict
import json
import datetime as dt
import math
import os
from pathlib import Path
import sys
from .artifacts import atomic_write
from .events import Event

# Identity normalization changed; replay schema-1 observations before reuse.
SCHEMA = 2


def usable_timestamp(value):
    if type(value) not in (int, float):
        return False
    try:
        if not math.isfinite(value):
            return False
        # Both canonical UTC evidence and local human rendering must work.
        dt.datetime.fromtimestamp(value, dt.timezone.utc)
        dt.datetime.fromtimestamp(value)
        return True
    except (OverflowError, OSError, ValueError):
        return False


class EventIndex:
    def __init__(self, home=None):
        home = Path.home() if home is None else home
        self.path = (
            Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
            / "agent-scan-index"
            / "events.json"
        )
        self.old, self.current = {}, {}
        self.parsed_sources = self.cache_hits = 0
        self.warned = False
        try:
            data = json.loads(self.path.read_text())
            if data.get("schema") == SCHEMA and isinstance(data.get("sources"), dict):
                self.old = data["sources"]
        except (OSError, ValueError, AttributeError):
            pass

    def warn(self):
        if not self.warned:
            print(
                "cache-scan: index unavailable; using fresh source evidence",
                file=sys.stderr,
            )
            self.warned = True

    def events(self, path, agent, parser):
        key = str(path.resolve())
        stat = path.stat()
        signature = [
            stat.st_dev,
            stat.st_ino,
            stat.st_size,
            stat.st_mtime_ns,
            stat.st_ctime_ns,
            agent,
        ]
        saved = self.old.get(key)
        if isinstance(saved, dict) and saved.get("signature") == signature:
            try:
                events = [Event(**event) for event in saved["events"]]
                # Reject syntactically valid but semantically corrupt cache entries.
                if not all(
                    usable_timestamp(e.timestamp)
                    and isinstance(e.sources, list)
                    and e.sources
                    and all(isinstance(source, dict)
                            and isinstance(source.get("path"), str)
                            and isinstance(source.get("line"), int)
                            and source["line"] > 0 for source in e.sources)
                    and all(isinstance(value, str) for value in
                            (e.session, e.agent, e.tool, e.command, e.output,
                             e.kind, e.origin, e.record_key))
                    and (e.call_id is None or isinstance(e.call_id, str))
                    and isinstance(e.child, int)
                    and isinstance(e.ambiguous, bool)
                    for e in events
                ):
                    raise ValueError("invalid cached event")
                self.cache_hits += 1
            except (KeyError, TypeError, ValueError, AttributeError):
                events = None
        else:
            events = None
        if events is None:
            events = list(parser(path, agent, True))
            self.parsed_sources += 1
        self.current[key] = {
            "signature": signature,
            "events": [asdict(e) for e in events],
        }
        return events

    def save(self):
        try:
            parent = self.path.parent
            if parent.is_symlink() or self.path.is_symlink():
                raise OSError("symlinked index")
            parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            parent.chmod(0o700)
            atomic_write(
                self.path,
                json.dumps(
                    {"schema": SCHEMA, "sources": self.current}, ensure_ascii=False
                ).encode(),
                replace=True,
            )
        except (OSError, ValueError):
            self.warn()

    def stats(self):
        return {
            "parsed_sources": self.parsed_sources,
            "cache_hits": self.cache_hits,
            "path": str(self.path),
        }
