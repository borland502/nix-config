---
name: ops-jira-integration
description: Use this skill when retrieving Jira tickets, analyzing requirements, updating ticket status, adding comments, transitioning issues, or reading/updating Confluence pages. Provides Jira/Confluence standalone (Server/Data Center) API patterns via direct REST calls or MCP.
origin: ECC
---

# Jira Integration Skill

Retrieve, analyze, and update Jira tickets (and Confluence pages) directly from your AI coding workflow.

> **This repo's policy: prefer direct REST API calls over CLI wrappers.**
> [chezmoi/dot_config/instructions/agent-defaults.md L12](../../../chezmoi/dot_config/instructions/agent-defaults.md): *"For Jira and Confluence operations, prefer direct REST/API-spec requests with configured tokens over dedicated `jira-cli` or `confluence-cli` wrappers."*
> Use the **REST API path (Option A below)** by default. The MCP integration (Option B) is a valid alternative when it's already configured for this user, but don't introduce or recommend `jira-cli`/`confluence-cli` wrappers.

## Standalone, Not Cloud

**The configured Jira (`jiraent.cms.gov`) and Confluence (`confluenceent.cms.gov`)
are self-hosted standalone (Server/Data Center) deployments, not Atlassian
Cloud.** Everything cloud-shaped fails here:

| Aspect | Cloud (do NOT use) | Standalone (use this) |
| ------ | ------------------ | --------------------- |
| Auth | Basic `-u email:api-token` | `Authorization: Bearer <PAT>` |
| Jira REST version | `/rest/api/3` | `/rest/api/2` |
| Comment/description bodies | ADF `{"type":"doc",...}` | Plain string (wiki markup) |
| Token origin | id.atlassian.com | Instance profile → Personal Access Tokens |
| Confluence page move | `PUT /pages/{id}` v2 API or `/move` | `PUT /rest/api/content/{id}` with `ancestors` (the `/move` endpoint 404s on this DC version) |

## When to Activate

- Fetching a Jira ticket to understand requirements
- Extracting testable acceptance criteria from a ticket
- Adding progress comments to a Jira issue
- Transitioning a ticket status (To Do → In Progress → Done)
- Linking merge requests or branches to a Jira issue
- Searching for issues by JQL query

## Prerequisites

### Option A: Direct REST API (default)

Use the Jira REST API **v2** (Server/DC) directly via `curl` or a helper script. This is the loud default per the policy above — no extra dependencies, no opaque wrapper layer, and the auth flow lives in plain shell.

**Credential files (sops-decrypted at activation, preferred over env vars):**

| File | Contents |
| ---- | -------- |
| `~/.config/ops-agent/jira-base-url` | Jira base URL **including** `/rest/api/2` (e.g. `https://jiraent.cms.gov/rest/api/2`) |
| `~/.config/ops-agent/jira-token` | Jira personal access token (PAT) — send as `Authorization: Bearer` |
| `~/.config/confluence/base-url` | Confluence base URL (e.g. `https://confluenceent.cms.gov`) |
| `~/.config/confluence/token` | Confluence PAT — send as `Authorization: Bearer` |

Populated by [home-manager/modules/sops.nix](../../../home-manager/modules/sops.nix) when `~/.config/sops/age/keys.txt` is present. See [sec-credentials](../sec-credentials/SKILL.md) for the full lookup precedence.

For Jira GETs, prefer the `jira-get <path>` helper (`~/.local/bin/jira-get`) over a hand-rolled `curl`: it owns the base-URL composition (the "base URL" already ends in `/rest/api/2` — prepending it again 404s) and turns non-2xx / non-JSON responses into clear stderr errors instead of a downstream `jq` parse failure. Paths are API-root-relative: `jira-get 'issue/KEY-123?fields=summary,status'`. For writes or Confluence, use the raw preamble:

```bash
JIRA_URL=$(/bin/cat ~/.config/ops-agent/jira-base-url)   # already ends in /rest/api/2
JIRA_TOKEN=$(/bin/cat ~/.config/ops-agent/jira-token)
CONFLUENCE_URL=$(/bin/cat ~/.config/confluence/base-url)
CONFLUENCE_TOKEN=$(/bin/cat ~/.config/confluence/token)
```

**To create a fresh token** (standalone instances — NOT id.atlassian.com):

1. In the Jira/Confluence instance: avatar → **Profile** → **Personal Access Tokens** → **Create token**
2. Add it to the encrypted secrets via [sec-sops-encrypt](../sec-sops-encrypt/SKILL.md) — never paste it into source code.

### Option B: MCP Server (alternative when already configured)

If the `mcp-atlassian` MCP server is already configured for the user, the JSON-RPC tooling layer is fine. Don't introduce it just for this task — REST is simpler. The MCP path has the same env-var requirements as REST.

**Add to your MCP config** (e.g., `~/.claude.json` → `mcpServers`):

```json
{
  "jira": {
    "command": "uvx",
    "args": ["mcp-atlassian==0.21.0"],
    "env": {
      "JIRA_URL": "https://jiraent.cms.gov",
      "JIRA_PERSONAL_TOKEN": "your-pat",
      "CONFLUENCE_URL": "https://confluenceent.cms.gov",
      "CONFLUENCE_PERSONAL_TOKEN": "your-pat"
    },
    "description": "Jira issue tracking — search, create, update, comment, transition"
  }
}
```

**Requirements:** Python 3.10+, `uvx` (from `uv`). For standalone instances use the `*_PERSONAL_TOKEN` variables (PAT/Bearer); the cloud-style `JIRA_EMAIL` + `JIRA_API_TOKEN` pair is wrong for this setup.

> **Security:** Never hardcode secrets. Prefer setting the URL/token values in your system environment (or sops-managed paths — see `sec-credentials`). Only use the MCP `env` block for local, uncommitted config files.

## MCP Tools Reference

When the `mcp-atlassian` MCP server is configured, these tools are available:

| Tool | Purpose | Example |
| ---- | ------- | ------- |
| `jira_search` | JQL queries | `project = PROJ AND status = "In Progress"` |
| `jira_get_issue` | Fetch full issue details by key | `PROJ-1234` |
| `jira_create_issue` | Create issues (Task, Bug, Story, Epic) | New bug report |
| `jira_update_issue` | Update fields (summary, description, assignee) | Change assignee |
| `jira_transition_issue` | Change status | Move to "In Review" |
| `jira_add_comment` | Add comments | Progress update |
| `jira_get_sprint_issues` | List issues in a sprint | Active sprint review |
| `jira_create_issue_link` | Link issues (Blocks, Relates to) | Dependency tracking |
| `jira_get_issue_development_info` | See linked PRs, branches, commits | Dev context |

> **Tip:** Always call `jira_get_transitions` before transitioning — transition IDs vary per project workflow.

## Direct REST API Reference (Jira standalone, v2)

`$JIRA_URL` below already ends in `/rest/api/2` (it comes straight from `~/.config/ops-agent/jira-base-url`). All auth is `Authorization: Bearer`.

### Fetch a Ticket

```bash
curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
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
curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
  "$JIRA_URL/issue/PROJ-1234/comment" | jq '.comments[] | {
    author: .author.displayName,
    created: .created[:10],
    body: .body
  }'

# Remote links (Confluence RFC pages, PRs, etc.)
curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
  "$JIRA_URL/issue/PROJ-1234/remotelink" | jq '[.[] | {title: .object.title, url: .object.url}]'
```

### Add a Comment

The v2 body is a **plain string** (wiki markup allowed) — not a cloud ADF document.

```bash
curl -s -X POST -H "Authorization: Bearer $JIRA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"body": "Your comment here"}' \
  "$JIRA_URL/issue/PROJ-1234/comment"
```

### Transition a Ticket

```bash
# 1. Get available transitions
curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
  "$JIRA_URL/issue/PROJ-1234/transitions" | jq '.transitions[] | {id, name: .name}'

# 2. Execute transition (replace TRANSITION_ID)
curl -s -X POST -H "Authorization: Bearer $JIRA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"transition": {"id": "TRANSITION_ID"}}' \
  "$JIRA_URL/issue/PROJ-1234/transitions"
```

### Search with JQL

```bash
curl -s -G -H "Authorization: Bearer $JIRA_TOKEN" \
  --data-urlencode "jql=project = PROJ AND status = 'In Progress'" \
  "$JIRA_URL/search"
```

## Direct REST API Reference (Confluence standalone)

Confluence Server/DC uses the v1 content API under `$CONFLUENCE_URL/rest/api/content`; the cloud v2 `/pages` API does not exist here.

### Fetch a Page (body, version, ancestors)

```bash
curl -s -H "Authorization: Bearer $CONFLUENCE_TOKEN" \
  "$CONFLUENCE_URL/rest/api/content/PAGE_ID?expand=body.storage,version,ancestors,space" | jq '{
    title, version: .version.number, space: .space.key,
    ancestors: [.ancestors[] | {id, title}]
  }'
```

The storage body is XHTML with `<ac:structured-macro>` elements; strip/convert it before analysis rather than reading it raw.

### Update or Re-parent a Page

Updates go through `PUT /rest/api/content/{id}` with the version bumped by one. To move a page, set `ancestors` in the same PUT — **the `/rest/api/content/{id}/move/...` endpoint 404s on this DC version.** Always re-fetch the current body first and send it back unchanged, or the update wipes the page content.

```bash
curl -s -X PUT -H "Authorization: Bearer $CONFLUENCE_TOKEN" \
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

For payloads this size, write a small Python/shell script under `~/.cache/claude` instead of inlining the JSON in the command string.

## Analyzing a Ticket

When retrieving a ticket for development or test automation, extract:

### 1. Testable Requirements

- **Functional requirements** — What the feature does
- **Acceptance criteria** — Conditions that must be met
- **Testable behaviors** — Specific actions and expected outcomes
- **User roles** — Who uses this feature and their permissions
- **Data requirements** — What data is needed
- **Integration points** — APIs, services, or systems involved

### 2. Test Types Needed

- **Unit tests** — Individual functions and utilities
- **Integration tests** — API endpoints and service interactions
- **E2E tests** — User-facing UI flows
- **API tests** — Endpoint contracts and error handling

### 3. Edge Cases & Error Scenarios

- Invalid inputs (empty, too long, special characters)
- Unauthorized access
- Network failures or timeouts
- Concurrent users or race conditions
- Boundary conditions
- Missing or null data
- State transitions (back navigation, refresh, etc.)

### 4. Structured Analysis Output

```text
Ticket: PROJ-1234
Summary: [ticket title]
Status: [current status]
Priority: [High/Medium/Low]
Test Types: Unit, Integration, E2E

Requirements:
1. [requirement 1]
2. [requirement 2]

Acceptance Criteria:
- [ ] [criterion 1]
- [ ] [criterion 2]

Test Scenarios:
- Happy Path: [description]
- Error Case: [description]
- Edge Case: [description]

Test Data Needed:
- [data item 1]
- [data item 2]

Dependencies:
- [dependency 1]
- [dependency 2]
```

## Updating Tickets

### When to Update

| Workflow Step | Jira Update |
| --- | --- |
| Start work | Transition to "In Progress" |
| Tests written | Comment with test coverage summary |
| Branch created | Comment with branch name |
| PR/MR created | Comment with link, link issue |
| Tests passing | Comment with results summary |
| PR/MR merged | Transition to "Done" or "In Review" |

### Comment Templates

**Starting Work:**

```text
Starting implementation for this ticket.
Branch: feat/PROJ-1234-feature-name
```

**Tests Implemented:**

```text
Automated tests implemented:

Unit Tests:
- [test file 1] — [what it covers]
- [test file 2] — [what it covers]

Integration Tests:
- [test file] — [endpoints/flows covered]

All tests passing locally. Coverage: XX%
```

**PR Created:**

```text
Pull request created:
[PR Title](https://github.com/org/repo/pull/XXX)

Ready for review.
```

**Work Complete:**

```text
Implementation complete.

PR merged: [link]
Test results: All passing (X/Y)
Coverage: XX%
```

## Security Guidelines

- **Never hardcode** Jira API tokens in source code or skill files
- **Always use** environment variables or a secrets manager
- **Add `.env`** to `.gitignore` in every project
- **Rotate tokens** immediately if exposed in git history
- **Use least-privilege** API tokens scoped to required projects
- **Validate** that credentials are set before making API calls — fail fast with a clear message

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

## Best Practices

- Update Jira as you go, not all at once at the end
- Keep comments concise but informative
- Link rather than copy — point to PRs, test reports, and dashboards
- Use @mentions if you need input from others
- Check linked issues to understand full feature scope before starting
- If acceptance criteria are vague, ask for clarification before writing code
