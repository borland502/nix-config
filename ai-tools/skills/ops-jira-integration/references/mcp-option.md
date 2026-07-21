# MCP Server (Option B — alternative when already configured)

If the `mcp-atlassian` MCP server is already configured for the user, the
JSON-RPC tooling layer is fine. Don't introduce it just for this task — REST is
simpler. The MCP path has the same credential requirements as REST.

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

**Requirements:** Python 3.10+, `uvx` (from `uv`). For standalone instances use
the `*_PERSONAL_TOKEN` variables (PAT/Bearer); the cloud-style `JIRA_EMAIL` +
`JIRA_API_TOKEN` pair is wrong for this setup.

> **Security:** Never hardcode secrets. Prefer setting the URL/token values in
> your system environment (or sops-managed paths — see `sec-credentials`). Only
> use the MCP `env` block for local, uncommitted config files.

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

> **Tip:** Always call `jira_get_transitions` before transitioning — transition
> IDs vary per project workflow.
