"""Common event identities and failure interpretation for local agent evidence."""

from dataclasses import dataclass, field, asdict
import json
import re


def decode(value):
    if isinstance(value, str):
        try:
            return json.loads(value)
        except ValueError:
            pass
    return value


def body(value):
    if isinstance(value, list):
        return " ".join(body(x) for x in value)
    if isinstance(value, dict):
        for key in ("text", "output", "content", "error"):
            if key in value:
                return body(value[key])
        return json.dumps(value)
    return str(value or "")


def command(arguments):
    args = decode(arguments)
    if isinstance(args, dict):
        return str(
            args.get(
                "cmd",
                args.get(
                    "command", args.get("file_path", args.get("session_id", args))
                ),
            )
        )
    return str(args or "")


def failure(output):
    value = decode(output)
    if isinstance(value, dict):
        if value.get("exit_code") is not None:
            return value["exit_code"] != 0
        return bool(value.get("isError") or value.get("is_error") or value.get("error"))
    text = body(value)
    match = re.search(r"(?:Process exited with code|exit_code[\"\s:]+)\s*(-?\d+)", text)
    if match:
        return int(match[1]) != 0
    if re.search(r"(?:Process|Script) running|session ID|cell ID", text):
        return False
    return bool(
        re.match(
            r"\s*(?:Error(?: executing tool| calling tool)?[: ]|Tool error|Traceback|Error parsing function call)",
            text,
        )
    )


def normalize_hook(value):
    value = decode(value)
    if not isinstance(value, dict):
        return {}
    result = {}
    for key, item in value.items():
        key = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", str(key))
        key = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", key).lower()
        result[key] = item
    return result


def heuristic_output(cmd, status):
    # status=ok is the current hook schema; stdout is its historic spelling.
    if status in ("stderr", "interrupted"):
        return True
    if re.search(
        r"cache-scan|failscan|error-.*sweep|session_.*\.log|\.cache/|gh run (?:view|download)",
        cmd,
    ):
        return False
    return not re.search(
        r"(?:bat|cat|rg|grep|head|tail)\b.*(?:\.md\b|\.jsonl\b|\.output\b)", cmd
    )


CATEGORIES = [
    (
        "stale-aws-creds",
        "ExpiredToken|security token included in the request is expired|InvalidClientTokenId|Unable to locate credentials|could not be found.*profile|ExpiredTokenException",
    ),
    (
        "stat-dialect",
        "stat: illegal option|cannot read file system information for .%|stat: option .* requires|unrecognized option '--format",
    ),
    ("zsh-nullglob", "no matches found|zsh: no matches"),
    (
        "zsh-word-split",
        "ambiguous argument '[^' ]+ [^']+'|empty string is not a valid pathspec",
    ),
    (
        "gh-graphql-jq",
        "is not defined|declared but not used|Unexpected .*RCURLY|GraphQL: |jq: error|jq: syntax error|Requires authentication|Could not resolve to a",
    ),
    ("jq-non-json-input", "jq: parse error"),
    (
        "quoting-heredoc",
        "parse error near|unexpected EOF|bad substitution|unmatched .|unexpected end of file|`\\\\?'.*unexpected",
    ),
    ("permission-denied", "[Pp]ermission denied|Operation not permitted|not permitted"),
    (
        "cmd-not-found",
        "command not found|: not found\\b|No such file or directory: .*bin",
    ),
    (
        "db-docker-conn",
        "Cannot connect to the Docker daemon|[Cc]onnection refused|could not connect to server|psql: error|No such container|Is the server running|ECONNREFUSED",
    ),
    (
        "network-tls",
        "Could not resolve host|Connection reset by peer|Connection timed out|curl: \\(\\d+\\)|SSL certificate problem|Recv failure",
    ),
    (
        "build-ts-node",
        "error TS\\d|Cannot find module|SyntaxError|ERR_MODULE|ELIFECYCLE|npm ERR!|tsc.*error",
    ),
    (
        "nix-build",
        "error: builder for|hash mismatch|attribute '.*' missing|infinite recursion|does not provide attribute|error: undefined variable",
    ),
    (
        "git-workflow",
        "^CONFLICT|\\bfatal:|! \\[rejected\\]|error: failed to push|error: pathspec|not a git repository",
    ),
    ("file-not-found", "No such file or directory|cannot access|does not exist"),
    ("other-failure", "[Ee]rror|[Ff]ailed|Traceback|Exception"),
]


def category(output):
    return next(
        (label for label, pattern in CATEGORIES if re.search(pattern, output, re.M)),
        None,
    )


def excerpt(output, limit=240):
    lines = output.splitlines()
    # Prefer useful error lines after protocol headers and repeated boilerplate.
    matches = [line for line in lines if category(line)]
    text = " ".join((matches or lines)).strip()
    return " ".join(text.split())[:limit]


@dataclass
class Event:
    timestamp: float
    session: str
    agent: str
    tool: str
    command: str
    output: str
    kind: str
    sources: list = field(default_factory=list)
    call_id: str | None = None
    child: int = 0
    origin: str = "native"
    record_key: str = ""
    ambiguous: bool = False

    def __iter__(self):
        return iter(
            (
                self.timestamp,
                self.session,
                self.agent,
                self.tool,
                self.command,
                self.output,
                self.kind,
            )
        )

    def __getitem__(self, key):
        return tuple(self)[key]

    def evidence(self, *, full_output=False, text_limit=2000):
        """Bound machine summaries; original sources and index retain full text."""
        value = asdict(self)
        for key in ("output", "command"):
            text = value[key]
            value[key + "_chars"] = len(text)
            value[key + "_truncated"] = not full_output and len(text) > text_limit
            if value[key + "_truncated"]:
                value[key] = text[:text_limit]
        value["excerpt"] = excerpt(self.output)
        value["category"] = category(self.output)
        return value


def reconcile(events):
    """Only join explicit execution IDs or corresponding mirrored records.

    Prefix hashes identify the same observation in a copied transcript while
    preserving identical repeated records at distinct positions. Similar text
    across representation types is uncertainty, never proof of one execution.
    """
    result, identities, records = [], {}, {}
    for event in events:
        identity = (
            (event.agent, event.session, event.call_id, event.child)
            if event.call_id
            else None
        )
        record = (event.agent, event.session, event.record_key, event.child, event.kind)
        previous = identities.get(identity) if identity else None
        mirrored = records.get(record) if event.record_key else None
        if (
            previous is None
            and mirrored is not None
            and mirrored.sources[0]["path"] != event.sources[0]["path"]
        ):
            previous = mirrored
        if previous is not None:
            previous.sources.extend(
                s for s in event.sources if s not in previous.sources
            )
            continue
        result.append(event)
        if identity:
            identities[identity] = event
        records[record] = event
    by_text = {}
    for event in result:
        if event.kind != "error":
            continue
        key = (event.agent, event.session, event.output)
        for prior in by_text.get(key, []):
            if prior.origin != event.origin and not (prior.call_id and event.call_id):
                prior.ambiguous = event.ambiguous = True
        by_text.setdefault(key, []).append(event)
    return result
