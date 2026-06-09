from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import anthropic

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------

_SECRET_JIRA_URL = Path.home() / ".config" / "ops-agent" / "jira-base-url"
_SECRET_JIRA_TOKEN = Path.home() / ".config" / "ops-agent" / "jira-token"
_SECRET_CONFLUENCE_URL = Path.home() / ".config" / "confluence" / "base-url"
_SECRET_CONFLUENCE_TOKEN = Path.home() / ".config" / "confluence" / "token"


def _jira_token() -> str:
    return _SECRET_JIRA_TOKEN.read_text().strip()


def _confluence_token() -> str:
    return _SECRET_CONFLUENCE_TOKEN.read_text().strip()


def _provision_script() -> Path | None:
    """Return the provision-secrets.sh path if locatable, else None.

    Checks XDG_STATE_HOME/chezmoi/nix-config-dir (written by the taskfile
    _record-nix-config-dir task) so the lookup survives the repo being moved.
    """
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    marker = state / "chezmoi" / "nix-config-dir"
    if marker.exists():
        candidate = (
            Path(marker.read_text().strip()) / "scripts" / "provision-secrets.sh"
        )
        if candidate.exists():
            return candidate
    return None


def _require_secrets() -> None:
    """Abort with a clear prompt if required sops secrets are absent."""
    missing = [
        p
        for p in [
            _SECRET_JIRA_URL,
            _SECRET_JIRA_TOKEN,
            _SECRET_CONFLUENCE_URL,
            _SECRET_CONFLUENCE_TOKEN,
        ]
        if not p.exists()
    ]
    if not missing:
        return

    print(
        "[ops-agent] Missing decrypted secret(s):\n"
        + "\n".join(f"  {p}" for p in missing),
        file=sys.stderr,
    )
    print(
        "[ops-agent] This usually means the age private key is absent or\n"
        "            'home-manager switch' has not been run since the key was added.",
        file=sys.stderr,
    )

    script = _provision_script()
    if script is not None:
        answer = (
            input("\nRun provision-secrets.sh now to add your age key? [y/N] ")
            .strip()
            .lower()
        )
        if answer == "y":
            os.execv("/usr/bin/env", ["/usr/bin/env", "bash", str(script)])
    else:
        print(
            "[ops-agent] Run scripts/provision-secrets.sh from your nix-config repo\n"
            "            to add your age key, then re-run 'home-manager switch'.",
            file=sys.stderr,
        )

    sys.exit(1)


def _jira_base_url() -> str:
    return _SECRET_JIRA_URL.read_text().strip()


def _confluence_base_url() -> str:
    return _SECRET_CONFLUENCE_URL.read_text().strip()


def _kion_creds() -> dict[str, str]:
    base = Path.home() / ".cache" / "kion-aws-cache"
    env: dict[str, str] = {}
    for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        f = base / key
        if f.exists():
            env[key] = f.read_text().strip()
    return env


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------


def _jira_request(method: str, path: str, body: Any = None) -> Any:
    url = f"{_jira_base_url()}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {_jira_token()}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        return {"error": exc.code, "reason": exc.reason, "body": exc.read().decode()}


def _aws(*args: str) -> str:
    env = {**os.environ, **_kion_creds()}
    result = subprocess.run(
        ["aws", *args],
        capture_output=True,
        text=True,
        env=env,
    )
    out = result.stdout + result.stderr
    return out[:4000]


# ---------------------------------------------------------------------------
# Tool implementations
# ---------------------------------------------------------------------------


def jira_get_issue(ticket_id: str) -> dict[str, Any]:
    fields = "summary,status,assignee,description"
    return _jira_request("GET", f"/issue/{ticket_id}?fields={fields}")


def jira_get_transitions(ticket_id: str) -> dict[str, Any]:
    return _jira_request("GET", f"/issue/{ticket_id}/transitions")


def jira_transition(ticket_id: str, status: str) -> dict[str, Any]:
    data = _jira_request("GET", f"/issue/{ticket_id}/transitions")
    if "error" in data:
        return data
    transitions: list[dict[str, Any]] = data.get("transitions", [])
    match = next(
        (t for t in transitions if status.lower() in t["to"]["name"].lower()),
        None,
    )
    if match is None:
        available = [t["to"]["name"] for t in transitions]
        return {"error": "no_match", "available": available}
    return _jira_request(
        "POST", f"/issue/{ticket_id}/transitions", {"transition": {"id": match["id"]}}
    )


def jira_comment(ticket_id: str, body: str) -> dict[str, Any]:
    return _jira_request("POST", f"/issue/{ticket_id}/comment", {"body": body})


def _cluster(ticket_id: str) -> str:
    return f"mdp-{ticket_id.lower()}-cluster"


def ecs_get_status(ticket_id: str, service: str) -> str:
    cluster = _cluster(ticket_id)
    svc = f"mdp-{ticket_id.lower()}-{service}"
    return _aws(
        "ecs",
        "list-tasks",
        "--cluster",
        cluster,
        "--service-name",
        svc,
        "--desired-status",
        "RUNNING",
    )


def ecs_force_deploy(ticket_id: str, service: str) -> str:
    cluster = _cluster(ticket_id)
    svc = f"mdp-{ticket_id.lower()}-{service}"
    return _aws(
        "ecs",
        "update-service",
        "--cluster",
        cluster,
        "--service",
        svc,
        "--force-new-deployment",
    )


def aws_cli(args: list[str]) -> str:
    return _aws(*args)


# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------

TOOL_HANDLERS: dict[str, Any] = {
    "jira_get_issue": lambda inp: jira_get_issue(inp["ticket_id"]),
    "jira_get_transitions": lambda inp: jira_get_transitions(inp["ticket_id"]),
    "jira_transition": lambda inp: jira_transition(inp["ticket_id"], inp["status"]),
    "jira_comment": lambda inp: jira_comment(inp["ticket_id"], inp["body"]),
    "ecs_get_status": lambda inp: ecs_get_status(inp["ticket_id"], inp["service"]),
    "ecs_force_deploy": lambda inp: ecs_force_deploy(inp["ticket_id"], inp["service"]),
    "aws_cli": lambda inp: aws_cli(inp["args"]),
}


def dispatch(tool_name: str, tool_input: dict[str, Any]) -> str:
    handler = TOOL_HANDLERS.get(tool_name)
    if handler is None:
        return json.dumps({"error": f"unknown tool: {tool_name}"})
    result = handler(tool_input)
    return json.dumps(result) if isinstance(result, (dict, list)) else str(result)


# ---------------------------------------------------------------------------
# Tool definitions (for API; cache_control on last entry)
# ---------------------------------------------------------------------------

TOOLS: list[dict[str, Any]] = [
    {
        "name": "jira_get_issue",
        "description": "Fetch Jira issue summary, status, assignee, and description.",
        "input_schema": {
            "type": "object",
            "properties": {
                "ticket_id": {
                    "type": "string",
                    "description": "Jira ticket ID, e.g. MDPMDD-797",
                }
            },
            "required": ["ticket_id"],
        },
    },
    {
        "name": "jira_get_transitions",
        "description": "List available workflow transitions for a Jira issue.",
        "input_schema": {
            "type": "object",
            "properties": {"ticket_id": {"type": "string"}},
            "required": ["ticket_id"],
        },
    },
    {
        "name": "jira_transition",
        "description": "Move a Jira issue to a new status by partial name match.",
        "input_schema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string"},
                "status": {
                    "type": "string",
                    "description": "Partial status name, e.g. 'In Progress'",
                },
            },
            "required": ["ticket_id", "status"],
        },
    },
    {
        "name": "jira_comment",
        "description": "Post a comment on a Jira issue.",
        "input_schema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string"},
                "body": {"type": "string", "description": "Comment text"},
            },
            "required": ["ticket_id", "body"],
        },
    },
    {
        "name": "ecs_get_status",
        "description": "List running ECS tasks for a service in the ticket's cluster.",
        "input_schema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string"},
                "service": {"type": "string", "enum": ["web", "data"]},
            },
            "required": ["ticket_id", "service"],
        },
    },
    {
        "name": "ecs_force_deploy",
        "description": "Force a new ECS deployment for a service in the ticket's cluster.",
        "input_schema": {
            "type": "object",
            "properties": {
                "ticket_id": {"type": "string"},
                "service": {"type": "string", "enum": ["web", "data"]},
            },
            "required": ["ticket_id", "service"],
        },
    },
    {
        "name": "aws_cli",
        "description": "Run an arbitrary AWS CLI command with Kion credentials. Output capped at 4000 chars.",
        "input_schema": {
            "type": "object",
            "properties": {
                "args": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "AWS CLI arguments excluding the 'aws' prefix, e.g. ['ecs', 'describe-clusters']",
                }
            },
            "required": ["args"],
        },
        "cache_control": {"type": "ephemeral"},
    },
]

SYSTEM = [
    {
        "type": "text",
        "text": (
            "You are an ops agent for the MDP platform. You help engineers manage Jira tickets "
            "and ECS deployments. Cluster names follow the pattern mdp-<ticket-id-lowercase>-cluster. "
            "Service names within a cluster are mdp-<ticket-id-lowercase>-web and mdp-<ticket-id-lowercase>-data. "
            "Always confirm destructive actions (force deploys, status transitions) with a short summary "
            "before reporting them as done."
        ),
        "cache_control": {"type": "ephemeral"},
    }
]

# ---------------------------------------------------------------------------
# Agent loop
# ---------------------------------------------------------------------------


def run(prompt: str) -> None:
    client = anthropic.Anthropic()
    messages: list[dict[str, Any]] = [{"role": "user", "content": prompt}]

    while True:
        with client.messages.stream(
            model="claude-sonnet-4-6",
            max_tokens=4096,
            system=SYSTEM,
            tools=TOOLS,
            messages=messages,
        ) as stream:
            response = stream.get_final_message()

        stop_reason = response.stop_reason
        messages.append({"role": "assistant", "content": response.content})

        if stop_reason == "end_turn":
            for block in response.content:
                if hasattr(block, "text"):
                    print(block.text)
            break

        if stop_reason != "tool_use":
            print(f"[ops-agent] unexpected stop_reason: {stop_reason}", file=sys.stderr)
            break

        tool_results: list[dict[str, Any]] = []
        for block in response.content:
            if block.type != "tool_use":
                continue
            print(f"[ops-agent] calling {block.name}({block.input})", file=sys.stderr)
            result = dispatch(block.name, block.input)
            tool_results.append(
                {"type": "tool_result", "tool_use_id": block.id, "content": result}
            )

        messages.append({"role": "user", "content": tool_results})


def _test_credentials() -> None:
    """Probe Jira and Confluence with read-only API calls and report pass/fail."""
    _require_secrets()
    ok = True

    # Jira: GET /myself (base URL already includes /rest/api/2)
    result = _jira_request("GET", "/myself")
    if "error" in result or not any(k in result for k in ("accountId", "key", "name")):
        print(f"[ops-agent] FAIL jira: {result}", file=sys.stderr)
        ok = False
    else:
        print(
            f"[ops-agent] OK   jira: logged in as {result.get('displayName')} ({result.get('emailAddress', '')})"
        )

    # Confluence: GET /rest/api/user/current
    confluence_url = _confluence_base_url()
    token = _confluence_token()
    req = urllib.request.Request(
        f"{confluence_url}/rest/api/user/current",
        method="GET",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            print(
                f"[ops-agent] FAIL confluence: non-JSON response: {body[:200]}",
                file=sys.stderr,
            )
            ok = False
            sys.exit(0 if ok else 1)
        if "accountId" not in data and "username" not in data and "userKey" not in data:
            print(f"[ops-agent] FAIL confluence: {data}", file=sys.stderr)
            ok = False
        else:
            name = data.get("displayName") or data.get("username", "")
            print(f"[ops-agent] OK   confluence: logged in as {name}")
    except urllib.error.HTTPError as exc:
        print(
            f"[ops-agent] FAIL confluence: HTTP {exc.code} {exc.reason}",
            file=sys.stderr,
        )
        ok = False

    sys.exit(0 if ok else 1)


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--test":
        _test_credentials()
        return
    _require_secrets()
    if len(sys.argv) < 2:
        print("Usage: ops-agent <prompt>", file=sys.stderr)
        print("       ops-agent --test   # verify credentials", file=sys.stderr)
        sys.exit(1)
    prompt = " ".join(sys.argv[1:])
    run(prompt)


if __name__ == "__main__":
    main()
