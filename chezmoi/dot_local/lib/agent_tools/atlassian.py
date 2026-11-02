"""Configured Atlassian JSON requests with bounded errors and safe pagination."""
import http.client
import json
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

class AtlassianError(RuntimeError):
    """Configuration, HTTP, transport, JSON or pagination failure."""

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Redirects may leak bearer tokens, including to login endpoints.
        return None

class Client:
    def __init__(self, root, token, *, timeout=60):
        self.root = root.rstrip("/")
        self.token = token
        self.timeout = timeout
        parsed = urllib.parse.urlsplit(self.root)
        if parsed.scheme not in ("http", "https") or not parsed.netloc or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise AtlassianError("invalid configured service root")

    @classmethod
    def configured(cls, service, *, timeout=60, config_dir=None):
        config = Path(config_dir) if config_dir else Path.home() / ".config" / ("ops-agent" if service == "jira" else "confluence")
        names = ("jira-base-url", "jira-token") if service == "jira" else ("base-url", "token")
        try:
            root, token = (config.joinpath(name).read_text().strip() for name in names)
        except OSError as exc:
            raise AtlassianError(f"missing or unreadable {service} configuration") from exc
        if not root or not token:
            raise AtlassianError(f"empty {service} configuration")
        if service == "confluence":
            root = root.rstrip("/") + "/rest/api"
        return cls(root, token, timeout=timeout)

    def url(self, path, *, current=None):
        parsed = urllib.parse.urlsplit(path)
        root = urllib.parse.urlsplit(self.root)
        if parsed.scheme or parsed.netloc:
            url = path
        elif current is not None:
            url = urllib.parse.urljoin(current, path)
        elif path.startswith(root.path.rstrip("/") + "/") and root.path:
            url = urllib.parse.urlunsplit((root.scheme, root.netloc, path, "", ""))
        else:
            path = path.lstrip("/")
            if self.root.endswith("/rest/api"):
                path = path.removeprefix("rest/api/")
            url = self.root + "/" + path
        dest = urllib.parse.urlsplit(url)
        decoded = urllib.parse.unquote(dest.path)
        if ((dest.scheme, dest.netloc) != (root.scheme, root.netloc)
                or dest.fragment or not dest.path.startswith(root.path.rstrip("/") + "/")
                or any(part in (".", "..") for part in decoded.split("/"))):
            raise AtlassianError("pagination/request URL leaves configured service root")
        return url

    def request(self, method, path, data=None, *, headers=None, raw=False, allow_empty=False, return_raw=False):
        url = self.url(path)
        hdrs = {"Accept": "application/json"}
        hdrs.update(headers or {})
        hdrs["Authorization"] = "Bearer " + self.token
        body = data
        if data is not None and not raw:
            body = json.dumps(data).encode()
            hdrs["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
        try:
            with urllib.request.build_opener(_NoRedirect).open(req, timeout=self.timeout) as response:
                payload = response.read()
        except urllib.error.HTTPError as exc:
            raise AtlassianError(f"HTTP {exc.code} on {method} request") from exc
        except (OSError, TimeoutError, urllib.error.URLError, http.client.HTTPException) as exc:
            raise AtlassianError("service request failed or timed out") from exc
        if not payload and allow_empty:
            return {}
        try:
            decoded = json.loads(payload)
        except (ValueError, UnicodeError) as exc:
            raise AtlassianError("empty or malformed JSON response") from exc
        return payload if return_raw else decoded

    def pages(self, path):
        """Yield Confluence result pages; reject cycles and links outside the API root."""
        current = self.url(path)
        seen = set()
        for _ in range(1000):
            if current in seen:
                raise AtlassianError("pagination cycle")
            seen.add(current)
            page = self.request("GET", current)
            if not isinstance(page, dict):
                raise AtlassianError("pagination response must be an object")
            yield page
            nxt = page.get("_links", {}).get("next")
            if not nxt:
                return
            current = self.url(nxt, current=current)
        raise AtlassianError("pagination limit exceeded")
