#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import selectors
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Any


class UsageError(RuntimeError):
    """The current Codex usage snapshot could not be read safely."""


@dataclass(frozen=True)
class UsageSummary:
    limit: Decimal
    used: Decimal
    remaining: Decimal
    used_percent: Decimal
    remaining_percent: int | None
    resets_at: int
    plan_type: str | None


def _send(proc: subprocess.Popen[str], message: dict[str, Any]) -> None:
    assert proc.stdin is not None
    proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    proc.stdin.flush()


def _read_response(
    proc: subprocess.Popen[str],
    selector: selectors.BaseSelector,
    request_id: int,
    deadline: float,
) -> dict[str, Any]:
    assert proc.stdout is not None
    while time.monotonic() < deadline:
        wait = min(0.25, max(0.0, deadline - time.monotonic()))
        if not selector.select(timeout=wait):
            if proc.poll() is not None:
                stderr = proc.stderr.read().strip() if proc.stderr else ""
                raise UsageError(
                    stderr or "Codex app-server exited without a response"
                )
            continue

        line = proc.stdout.readline()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError as exc:
            raise UsageError("Codex app-server returned invalid JSON") from exc
        if message.get("id") != request_id:
            continue
        if "error" in message:
            error = message["error"]
            detail = (
                error.get("message", str(error))
                if isinstance(error, dict)
                else str(error)
            )
            raise UsageError(detail)
        result = message.get("result")
        if not isinstance(result, dict):
            raise UsageError(f"request {request_id} returned no result object")
        return result

    raise UsageError("Codex usage request timed out")


def request_rate_limits(
    codex_bin: str, timeout: float = 15.0
) -> dict[str, Any]:
    proc = subprocess.Popen(
        [codex_bin, "app-server", "--listen", "stdio://"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    selector = selectors.DefaultSelector()
    assert proc.stdout is not None
    selector.register(proc.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout

    try:
        _send(
            proc,
            {
                "method": "initialize",
                "id": 1,
                "params": {
                    "clientInfo": {
                        "name": "nix-config-codex-usage",
                        "title": "Codex Usage",
                        "version": "1.0.0",
                    },
                    "capabilities": {"experimentalApi": True},
                },
            },
        )
        _read_response(proc, selector, 1, deadline)
        _send(proc, {"method": "initialized", "params": {}})
        _send(
            proc,
            {
                "method": "account/rateLimits/read",
                "id": 2,
                "params": None,
            },
        )
        return _read_response(proc, selector, 2, deadline)
    finally:
        selector.close()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        for pipe in (proc.stdin, proc.stdout, proc.stderr):
            if pipe is not None:
                pipe.close()


def summarize_usage(response: dict[str, Any]) -> UsageSummary:
    buckets = response.get("rateLimitsByLimitId") or {}
    bucket = buckets.get("codex") or response.get("rateLimits") or {}
    individual = bucket.get("individualLimit")
    if not isinstance(individual, dict):
        raise UsageError("Codex response did not include individualLimit")

    try:
        limit = Decimal(str(individual["limit"]))
        used = Decimal(str(individual["used"]))
        resets_at = int(individual["resetsAt"])
    except (KeyError, InvalidOperation, TypeError, ValueError) as exc:
        raise UsageError("Codex individualLimit contained invalid values") from exc
    if limit <= 0:
        raise UsageError("Codex credit limit must be greater than zero")

    remaining = max(limit - used, Decimal(0))
    return UsageSummary(
        limit=limit,
        used=used,
        remaining=remaining,
        used_percent=(used / limit) * Decimal(100),
        remaining_percent=individual.get("remainingPercent"),
        resets_at=resets_at,
        plan_type=bucket.get("planType"),
    )


def format_summary(summary: UsageSummary) -> str:
    reset = datetime.fromtimestamp(summary.resets_at).astimezone()
    displayed = (
        f"{summary.remaining_percent}% left"
        if summary.remaining_percent is not None
        else "unavailable"
    )
    return "\n".join(
        [
            f"Used: {summary.used:,.2f} of {summary.limit:,.0f} credits "
            f"({summary.used_percent:,.2f}%)",
            f"Remaining: {summary.remaining:,.2f} credits ({displayed})",
            f"Reset: {reset:%Y-%m-%d %I:%M %p %Z}",
            f"Backend plan type: {summary.plan_type or 'unavailable'}",
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Read current Codex credit usage")
    parser.add_argument("--codex-bin", default=shutil.which("codex"))
    parser.add_argument("--timeout", type=float, default=15.0)
    args = parser.parse_args()
    if not args.codex_bin:
        parser.error("codex executable not found; pass --codex-bin")

    try:
        response = request_rate_limits(args.codex_bin, args.timeout)
        print(format_summary(summarize_usage(response)))
    except UsageError as exc:
        print(f"codex-usage: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
