#!/usr/bin/env python3
"""
Profile wordgen startup cost under different dataset/cache scenarios.

Scenarios tested
----------------
cold_gob   : all.gob absent  – first run must JSON-decode and write the sidecar
warm_gob   : all.gob present – gob sidecar read directly, no JSON decoding
embedded   : dataset forced to embedded://all.json.zst via env var
json_cache : dataset forced to $XDG_CACHE_HOME/wordgen/all.json (if it exists)

Usage
-----
    python3 scripts/profile_startup.py [--binary BINARY] [--runs N]
    python3 scripts/profile_startup.py --binary ./tmp/deploy-build/wordgen --runs 10
"""

from __future__ import annotations

import argparse
import os
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def xdg_cache_home() -> Path:
    env = os.environ.get("XDG_CACHE_HOME", "").strip()
    return Path(env) if env else Path.home() / ".cache"


def resolve_binary(binary: str) -> Path:
    resolved = shutil.which(binary)
    if resolved is None:
        candidate = Path(binary)
        if candidate.is_file():
            return candidate.resolve()
        sys.exit(f"error: binary not found: {binary!r}")
    return Path(resolved)


def run_once(binary: Path, extra_env: dict[str, str] | None = None) -> float:
    """Return elapsed wall-clock seconds for one invocation of `binary generate`."""
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    start = time.perf_counter()
    result = subprocess.run(
        [str(binary), "generate"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    elapsed = time.perf_counter() - start
    if result.returncode != 0:
        print(f"  warning: binary exited with code {result.returncode}", file=sys.stderr)
    return elapsed


def run_scenario(
    label: str,
    binary: Path,
    runs: int,
    setup: "Callable[[], None] | None" = None,
    extra_env: dict[str, str] | None = None,
) -> list[float]:
    print(f"\nScenario: {label}")
    times: list[float] = []
    for i in range(1, runs + 1):
        if setup:
            setup()
        elapsed = run_once(binary, extra_env)
        ms = elapsed * 1000
        times.append(ms)
        print(f"  run {i:>2}: {ms:.1f}ms")
    avg = statistics.mean(times)
    med = statistics.median(times)
    print(f"  avg={avg:.1f}ms  median={med:.1f}ms  min={min(times):.1f}ms  max={max(times):.1f}ms")
    return times


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Profile wordgen startup cost across dataset/cache scenarios."
    )
    parser.add_argument(
        "--binary",
        default="wordgen",
        help="path or name of the wordgen binary (default: wordgen)",
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=10,
        help="number of timed iterations per scenario (default: 10)",
    )
    args = parser.parse_args()

    binary = resolve_binary(args.binary)
    runs = args.runs

    cache_dir = xdg_cache_home() / "wordgen"
    gob_path = cache_dir / "all.gob"
    json_path = cache_dir / "all.json"

    print(f"binary  : {binary}")
    print(f"runs    : {runs}")
    print(f"gob     : {gob_path}")
    print(f"json    : {json_path}")

    results: list[tuple[str, list[float]]] = []

    # ------------------------------------------------------------------
    # Scenario 1 – cold gob (no sidecar; JSON-decode + gob write on every run)
    # ------------------------------------------------------------------
    def cold_setup() -> None:
        gob_path.unlink(missing_ok=True)

    results.append((
        "cold_gob",
        run_scenario(
            "cold_gob  (no sidecar; JSON-decode + write gob each run)",
            binary,
            runs,
            setup=cold_setup,
            extra_env={"WORDGEN_GENERATE_DATASET": "embedded://all.json.zst"},
        ),
    ))

    # ------------------------------------------------------------------
    # Scenario 2 – warm gob (sidecar present; gob decode only)
    # Ensure gob exists first by doing one priming run.
    # ------------------------------------------------------------------
    gob_path.unlink(missing_ok=True)
    print("\nPriming warm_gob sidecar…", end=" ", flush=True)
    run_once(binary, extra_env={"WORDGEN_GENERATE_DATASET": "embedded://all.json.zst"})
    if gob_path.exists():
        print("done")
    else:
        print("WARNING: gob not written – warm scenario may not reflect cache hit")

    results.append((
        "warm_gob",
        run_scenario(
            "warm_gob  (sidecar present; gob decode only)",
            binary,
            runs,
            extra_env={"WORDGEN_GENERATE_DATASET": "embedded://all.json.zst"},
        ),
    ))

    # ------------------------------------------------------------------
    # Scenario 3 – embedded (force in-memory zstd → JSON, bypass gob)
    # ------------------------------------------------------------------
    results.append((
        "embedded",
        run_scenario(
            "embedded  (forced embedded://all.json.zst; in-memory zstd + JSON)",
            binary,
            runs,
            extra_env={"WORDGEN_GENERATE_DATASET": "embedded://all.json.zst"},
        ),
    ))

    # ------------------------------------------------------------------
    # Scenario 4 – explicit all.json from cache (if it exists)
    # ------------------------------------------------------------------
    if json_path.exists():
        results.append((
            "json_cache",
            run_scenario(
                "json_cache (explicit all.json from cache; JSON decode, no gob)",
                binary,
                runs,
                extra_env={"WORDGEN_GENERATE_DATASET": str(json_path)},
            ),
        ))
    else:
        print(f"\nScenario: json_cache — skipped ({json_path} not found)")

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    label_w = max(len(label) for label, _ in results)
    print()
    print("=" * (label_w + 22))
    print(f"{'Scenario':<{label_w}}  {'Avg (ms)':>9}  {'Median (ms)':>11}")
    print("-" * (label_w + 22))
    for label, times in results:
        print(f"{label:<{label_w}}  {statistics.mean(times):>9.1f}  {statistics.median(times):>11.1f}")
    print("=" * (label_w + 22))
    print()


if __name__ == "__main__":
    main()
