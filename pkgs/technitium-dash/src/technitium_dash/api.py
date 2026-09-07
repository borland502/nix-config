"""Technitium DNS HTTP API client."""

from __future__ import annotations

from typing import Any, Self

import httpx

# Decoded JSON from the Technitium API. `Any` is the honest value type: the
# server returns heterogeneous payloads and this client does not model them.
JsonDict = dict[str, Any]

# What the API accepts as a query-string value. Narrower than `object` so httpx
# accepts the mapping without a cast.
QueryValue = str | int | float | bool | None


class ApiError(Exception):
    """Raised when the Technitium API is unreachable or answers not-ok."""


class Technitium:
    """Read-only client for the Technitium DNS API.

    Uses one pooled httpx client for the process lifetime: the panel polls four
    endpoints every few seconds, and reconnecting for each was the bulk of a
    refresh against a remote server.
    """

    # Pages walked at most when filling a filtered feed. A chatty host can own
    # most of a page on its own, so one page of `count` would leave the panel
    # part-empty once its entries are dropped. Bounded because this runs on a
    # short refresh: a busy server with everything excluded must not walk the
    # log forever.
    MAX_PAGES = 6

    def __init__(
        self,
        url: str,
        token: str,
        timeout: float = 6.0,
        exclude: tuple[str, ...] = (),
        max_per_name: int = 0,
    ) -> None:
        """Configure a client for one server; no request is made until called."""
        self.url = url.rstrip("/")
        self.token = token
        self.exclude = exclude
        self.max_per_name = max_per_name
        self._client = httpx.Client(timeout=timeout, follow_redirects=True)

    def close(self) -> None:
        """Release the pooled connections."""
        self._client.close()

    def __enter__(self) -> Self:
        """Return self so the client can be used as a context manager."""
        return self

    def __exit__(self, *_exc: object) -> None:
        """Close the pooled connections on exit."""
        self.close()

    def call(self, path: str, **params: QueryValue) -> JsonDict:
        """Perform one authenticated GET and unwrap the API envelope."""
        params["token"] = self.token
        try:
            resp = self._client.get(f"{self.url}/{path.lstrip('/')}", params=params)
            resp.raise_for_status()
            payload = resp.json()
        except httpx.HTTPStatusError as exc:
            msg = f"HTTP {exc.response.status_code}"
            raise ApiError(msg) from exc
        except httpx.HTTPError as exc:
            msg = str(exc)
            raise ApiError(msg) from exc
        except ValueError as exc:
            msg = "bad JSON from server"
            raise ApiError(msg) from exc
        if payload.get("status") != "ok":
            msg = payload.get("errorMessage") or "api returned not-ok"
            raise ApiError(msg)
        response: JsonDict = payload.get("response", {})
        return response

    def stats(self, window: str = "LastHour") -> JsonDict:
        """Return the dashboard statistics for ``window``."""
        return self.call("dashboard/stats/get", type=window, utcFormat="false")

    def version(self) -> str:
        """Return the server version, or ``?`` when the check is unavailable."""
        try:
            current: str = self.call("user/checkForUpdate").get("currentVersion", "?")
        except ApiError:
            return "?"
        return current

    @staticmethod
    def _qname(entry: JsonDict) -> str:
        return (entry.get("qname") or "").rstrip(".").lower()

    def _excluded(self, entry: JsonDict) -> bool:
        # Match the name itself and anything under it, the way a zone reads:
        # excluding `svc.example.lan` also drops `a.svc.example.lan`.
        name = self._qname(entry)
        return any(name == pat or name.endswith("." + pat) for pat in self.exclude)

    def _page(self, n: int, size: int) -> list[JsonDict]:
        resp = self.call(
            "logs/query",
            name="Query Logs (Sqlite)",
            classPath="QueryLogsSqlite.App",
            pageNumber=n,
            entriesPerPage=size,
            descendingOrder="true",
        )
        entries: list[JsonDict] = resp.get("entries", []) or []
        return entries

    def _keep(
        self,
        entries: list[JsonDict],
        kept: list[JsonDict],
        shown: dict[str, int],
        count: int,
    ) -> None:
        """Append the entries that survive exclusion and the per-name cap."""
        for q in entries:
            if self._excluded(q):
                continue
            if self.max_per_name:
                # The cap is per name across the whole visible feed, not per
                # page — a name at its limit on page 1 must stay at that limit
                # when page 2 supplies more of it.
                name = self._qname(q)
                if shown.get(name, 0) >= self.max_per_name:
                    continue
                shown[name] = shown.get(name, 0) + 1
            kept.append(q)
            if len(kept) >= count:
                return

    def queries(self, count: int) -> list[JsonDict]:
        """Return recent queries with exclusions and the per-name cap applied.

        The Query Logs (Sqlite) app is optional; callers treat failure as "no
        live feed available" rather than fatal. The API has no server-side
        exclusion or per-name cap, so both happen here — which means
        over-fetching: dropping two thirds of a page would show a third of a
        screen, reading as "DNS went quiet" rather than "the noise is hidden".
        Walk pages until the feed is full instead.
        """
        if not self.exclude and not self.max_per_name:
            return self._page(1, count)

        per_page = count * 2
        kept: list[JsonDict] = []
        shown: dict[str, int] = {}
        for n in range(1, self.MAX_PAGES + 1):
            try:
                entries = self._page(n, per_page)
            except ApiError:
                # Page 1 failing means no feed at all — let the caller show
                # that. A later page failing mid-walk should not discard the
                # entries already in hand.
                if n == 1:
                    raise
                break
            self._keep(entries, kept, shown, count)
            if len(kept) >= count or len(entries) < per_page:
                break
        return kept[:count]
