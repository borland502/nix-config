"""Shared command-line adapter for Atlassian GET requests."""
import argparse
import sys

from agent_tools.atlassian import AtlassianError, Client


def get_main(service: str, *, argv=None, prog=None) -> int:
    parser = argparse.ArgumentParser(
        prog=prog,
        description="GET a configured Atlassian API path and validate the JSON response.",
    )
    parser.add_argument("path")
    args = parser.parse_args(argv)
    try:
        payload = Client.configured(service).request("GET", args.path, return_raw=True)
        sys.stdout.buffer.write(payload)
        return 0
    except (AtlassianError, OSError) as exc:
        print(f"{service}-get: {exc}", file=sys.stderr)
        return 1
