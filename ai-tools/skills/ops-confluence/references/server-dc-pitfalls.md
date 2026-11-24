# Confluence Server/DC pitfalls

Each of these has actually happened on this instance.

## An update without a body wipes the page

`PUT` with no `body` blanks the content. Always re-fetch and send the current
body back unless you are deliberately replacing it. `confluence-page update`
does this for you — `--body-file` is optional precisely so that retitling and
re-parenting cannot destroy content. Empty or whitespace-only replacement
bodies are rejected before the write.

## Bind replacements to the version you edited

A body replacement requires `--expected-version N`, where N comes from the
original page read used to prepare that body. The helper compares N with the
live version and refuses a stale draft before writing. Read the latest page and
reconcile intervening edits after a mismatch; do not merely substitute its newer
version number. Metadata-only updates may optionally assert a version too.

The outgoing version is current + 1. A concurrent edit after the check still
produces a server `409`; writes are not automatically retried.

## `/move` does not exist — re-parent through `ancestors`

`PUT`/`POST` on `/rest/api/content/{id}/move/append/{target}` returns
`404 HTTP 404 Not Found` on this DC version, in an XML body that will also break
a `jq` pipe. Set `ancestors` in the normal update `PUT` instead:

```bash
confluence-page update 1380859735 --parent 1015307227
```

## Re-uploading an attachment name 400s

```text
HTTP 400 Cannot add a new attachment with same file name as an existing
attachment: mdpmdd-879-sequence.svg
```

`POST /child/attachment` only *creates*. To add a new version of an existing
file, `POST` to that attachment's own data endpoint,
`/child/attachment/{attachmentId}/data`. `confluence-page attach` looks up the
existing attachments by name and picks the right endpoint automatically, so the
same command both creates and updates. Lookup follows every result page and
refreshes after each upload, so repeated basenames in one invocation update the
attachment just created. `attachments` and `children` also follow all pages;
`children --limit` controls page size, not the total returned.

## Uploads need the XSRF opt-out header

Multipart uploads without `X-Atlassian-Token: no-check` are rejected. (`nocheck`
also works; `no-check` is the current spelling.)

## Confluence sniffs media types, and gets SVG wrong

An SVG uploaded without an explicit `Content-Type` lands as
`application/octet-stream` and downloads instead of rendering. Send
`image/svg+xml` explicitly — `confluence-page` forces the type for `.svg`,
`.drawio`, and `.mmd`.

## Error bodies are HTML, so `jq` lies about the failure

A failing call often returns an HTML error page. Piping that to `jq` produces
`parse error: Invalid numeric literal`, which looks like a malformed-JSON bug
and hides the real 401/404. Both helpers report HTTP status and method, adding
a bounded, sanitized message when the API supplies recognized JSON error fields.
They redact credentials and omit raw HTML or malformed response bodies. If you
must use raw `curl`, capture `%{http_code}` and check it before parsing.

## The two base URLs are not symmetric

`~/.config/ops-agent/jira-base-url` **ends with** `/rest/api/2`;
`~/.config/confluence/base-url` is the **bare host**. A path shaped for Jira
404s against Confluence. The helpers own this composition — pass paths relative
to the REST root and do not prepend `/rest/api`.

## `Connection reset by peer` is usually the VPN

Transient and bursty. Retry 2–3 times with short backoff before re-diagnosing.
