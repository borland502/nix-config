---
name: ops-jira-integration
description: Use when creating, updating, or transitioning Jira issues, adding comments or attachments, running JQL searches, extracting testable requirements from a ticket, or reading/updating Confluence pages on the standalone (Server/DC) instances. NOT needed for a plain ticket read — use `jira-get 'issue/KEY-123?fields=summary,status'` or `ops-agent --tool jira_get_issue '{"ticket_id":"KEY-123"}'` directly, without loading this skill.
origin: ECC
---

# Jira Integration Skill

Write to Jira tickets and Confluence pages (and analyze tickets) directly from
your AI coding workflow.

> **This repo's policy: prefer direct REST API calls over CLI wrappers.**
> [chezmoi/dot_config/instructions/agent-defaults.md L12](../../../chezmoi/dot_config/instructions/agent-defaults.md): *"For Jira and Confluence operations, prefer direct REST/API-spec requests with configured tokens over dedicated `jira-cli` or `confluence-cli` wrappers."*
> Use the **REST path** by default; the MCP integration is a valid alternative
> only when it's already configured for this user.

## Reads Don't Need This Skill

For lookups (summary, status, description, comments), use the pre-built
helpers and stop here:

- `jira-get 'issue/KEY-123?fields=summary,status'` — any Jira GET, prints JSON
  for `jq`; paths are API-root-relative (helper owns the `/rest/api/2` suffix)
- `ops-agent --tool jira_get_issue '{"ticket_id":"KEY-123"}'` — issue details;
  also `jira_get_transitions`, and (writes) `jira_comment`, `jira_transition`

Both are cataloged in `~/.config/instructions/agent-reference.md`. This skill
earns its load for **writes, JQL, attachments, Confluence, and analysis**.

## Standalone, Not Cloud

**The configured Jira (`jiraent.cms.gov`) and Confluence
(`confluenceent.cms.gov`) are self-hosted standalone (Server/Data Center)
deployments, not Atlassian Cloud.** Everything cloud-shaped fails here:

| Aspect | Cloud (do NOT use) | Standalone (use this) |
| ------ | ------------------ | --------------------- |
| Auth | Basic `-u email:api-token` | `Authorization: Bearer <PAT>` |
| Jira REST version | `/rest/api/3` | `/rest/api/2` |
| Comment/description bodies | ADF `{"type":"doc",...}` | Plain string (wiki markup) |
| Token origin | id.atlassian.com | Instance profile → Personal Access Tokens |
| Confluence page move | `PUT /pages/{id}` v2 API or `/move` | `PUT /rest/api/content/{id}` with `ancestors` (the `/move` endpoint 404s on this DC version) |

## Credentials

Sops-decrypted at activation (preferred over env vars); populated by
[home-manager/modules/sops.nix](../../../home-manager/modules/sops.nix) when
`~/.config/sops/age/keys.txt` is present. See
[sec-credentials](../sec-credentials/SKILL.md) for lookup precedence.

| File | Contents |
| ---- | -------- |
| `~/.config/ops-agent/jira-base-url` | Jira base URL **including** `/rest/api/2` |
| `~/.config/ops-agent/jira-token` | Jira PAT — send as `Authorization: Bearer` |
| `~/.config/confluence/base-url` | Confluence base URL (no API suffix) |
| `~/.config/confluence/token` | Confluence PAT — send as `Authorization: Bearer` |

Never hardcode tokens, keep them out of argv (the recipes file shows the
stdin-config pattern), and validate credentials exist before calling — fail
fast with a clear message. Token creation steps are in the recipes file.

## References (read the one you need)

- [references/rest-recipes.md](references/rest-recipes.md) — the default
  path: `jira_curl`/`confluence_curl` helpers (token out of argv), Jira
  write/transition/JQL recipes, Confluence fetch/update/re-parent, fresh-token
  steps, and the troubleshooting table (401/403/404, ADF-vs-plain-string,
  cloud-endpoint 404s, VPN resets).
- [references/workflow-templates.md](references/workflow-templates.md) —
  extracting testable requirements/acceptance criteria from a ticket, the
  structured analysis output format, when to update a ticket during the dev
  workflow, and comment templates.
- [references/mcp-option.md](references/mcp-option.md) — the `mcp-atlassian`
  MCP server alternative: config, requirements, and tool reference. Only when
  it's already configured; don't introduce it for a one-off task.
