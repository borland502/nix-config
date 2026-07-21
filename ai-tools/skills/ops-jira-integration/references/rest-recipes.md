# Direct REST Recipes (Option A — Jira v2 + Confluence Server/DC)

`$JIRA_URL` below already ends in `/rest/api/2` (it comes straight from
`~/.config/ops-agent/jira-base-url`). All auth is `Authorization: Bearer`.

```bash
JIRA_URL=$(/bin/cat ~/.config/ops-agent/jira-base-url)   # already ends in /rest/api/2
CONFLUENCE_URL=$(/bin/cat ~/.config/confluence/base-url)
```

**Keep the token out of argv.** A `-H "Authorization: Bearer $TOKEN"` argument
expands the secret into process argv — visible in `ps` and captured verbatim by
the log-bash PostToolUse hook into the session logs. Pass the header on stdin
via curl's config instead (adapted from ECC's credentials-out-of-argv fix) and
use these helpers in every recipe below:

```bash
jira_curl() {
  printf 'header = "Authorization: Bearer %s"\n' "$(/bin/cat ~/.config/ops-agent/jira-token)" |
    curl -s -K - "$@"
}
confluence_curl() {
  printf 'header = "Authorization: Bearer %s"\n' "$(/bin/cat ~/.config/confluence/token)" |
    curl -s -K - "$@"
}
```

For plain Jira GETs the `jira-get` helper already does all of this — these
helpers are for writes and Confluence.

## Jira

### Fetch a Ticket

```bash
jira_curl \
  "$JIRA_URL/issue/PROJ-1234" | jq '{
    key: .key,
    summary: .fields.summary,
    status: .fields.status.name,
    priority: .fields.priority.name,
    type: .fields.issuetype.name,
    assignee: .fields.assignee.displayName,
    labels: .fields.labels,
    description: .fields.description
  }'
```

### Fetch Comments and Remote Links

```bash
jira_curl \
  "$JIRA_URL/issue/PROJ-1234/comment" | jq '.comments[] | {
    author: .author.displayName,
    created: .created[:10],
    body: .body
  }'

# Remote links (Confluence RFC pages, PRs, etc.)
jira_curl \
  "$JIRA_URL/issue/PROJ-1234/remotelink" | jq '[.[] | {title: .object.title, url: .object.url}]'
```

### Add a Comment

The v2 body is a **plain string** (wiki markup allowed) — not a cloud ADF document.

```bash
jira_curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"body": "Your comment here"}' \
  "$JIRA_URL/issue/PROJ-1234/comment"
```

### Transition a Ticket

```bash
# 1. Get available transitions
jira_curl \
  "$JIRA_URL/issue/PROJ-1234/transitions" | jq '.transitions[] | {id, name: .name}'

# 2. Execute transition (replace TRANSITION_ID)
jira_curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"transition": {"id": "TRANSITION_ID"}}' \
  "$JIRA_URL/issue/PROJ-1234/transitions"
```

### Search with JQL

```bash
jira_curl -G \
  --data-urlencode "jql=project = PROJ AND status = 'In Progress'" \
  "$JIRA_URL/search"
```

## Confluence

Confluence Server/DC uses the v1 content API under
`$CONFLUENCE_URL/rest/api/content`; the cloud v2 `/pages` API does not exist here.

### Fetch a Page (body, version, ancestors)

```bash
confluence_curl \
  "$CONFLUENCE_URL/rest/api/content/PAGE_ID?expand=body.storage,version,ancestors,space" | jq '{
    title, version: .version.number, space: .space.key,
    ancestors: [.ancestors[] | {id, title}]
  }'
```

The storage body is XHTML with `<ac:structured-macro>` elements; strip/convert
it before analysis rather than reading it raw.

### Update or Re-parent a Page

Updates go through `PUT /rest/api/content/{id}` with the version bumped by one.
To move a page, set `ancestors` in the same PUT — **the
`/rest/api/content/{id}/move/...` endpoint 404s on this DC version.** Always
re-fetch the current body first and send it back unchanged, or the update wipes
the page content.

```bash
confluence_curl -X PUT \
  -H "Content-Type: application/json" \
  -d '{
    "id": "PAGE_ID", "type": "page", "title": "Current Title",
    "space": {"key": "SPACEKEY"},
    "ancestors": [{"id": "NEW_PARENT_ID"}],
    "body": {"storage": {"value": "<refetched storage body>", "representation": "storage"}},
    "version": {"number": CURRENT_PLUS_ONE, "minorEdit": true, "message": "why"}
  }' \
  "$CONFLUENCE_URL/rest/api/content/PAGE_ID"
```

For payloads this size, write a small Python/shell script under
`~/.cache/claude` instead of inlining the JSON in the command string.

## Creating a Fresh Token

Standalone instances — NOT id.atlassian.com:

1. In the Jira/Confluence instance: avatar → **Profile** → **Personal Access
   Tokens** → **Create token**
2. Add it to the encrypted secrets via
   [sec-sops-encrypt](../../sec-sops-encrypt/SKILL.md) — never paste it into
   source code.

## Troubleshooting

| Error | Cause | Fix |
| --- | --- | --- |
| `401 Unauthorized` | Invalid or expired PAT, or basic auth used | Send `Authorization: Bearer`; regenerate the PAT in the instance profile (NOT id.atlassian.com) |
| `403 Forbidden` | Token lacks project permissions | Check token scopes and project access |
| `404 Not Found` | Wrong ticket key or base URL | Verify the base-url file contents and ticket key; remember the Jira base URL already includes `/rest/api/2` |
| `404` on `/rest/api/3/...` | Cloud API version against a standalone instance | Use `/rest/api/2` |
| `400` posting a comment | ADF document body sent to Server/DC | Body is a plain string: `{"body": "text"}` |
| `404` on Confluence `/move` or `/api/v2/pages` | Cloud-only endpoints | Use `PUT /rest/api/content/{id}` with `ancestors` + version bump |
| `spawn uvx ENOENT` | IDE cannot find `uvx` on PATH | Use full path (e.g., `~/.local/bin/uvx`) or set PATH in `~/.zprofile` |
| Connection timeout | Network/VPN issue | Check VPN connection and firewall rules |
| `Connection reset by peer` | VPN-path flakiness (transient; recurs in bursts) | Retry the same request 2-3x with short backoff (`sleep 2`, `sleep 5`) before re-diagnosing; prefer direct REST with the token over CLI wrappers (standing rule) |
