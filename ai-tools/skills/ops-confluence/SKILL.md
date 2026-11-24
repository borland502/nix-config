---
name: ops-confluence
description: Use when reading or writing Confluence pages, uploading or replacing attachments, embedding images or diagrams in a page, re-parenting or moving a page, or debugging a Confluence REST failure (HTTP 400 "same file name", 404 on /move or /api/v2/pages, a blanked page body, a jq parse error on an HTML error body). Covers the self-hosted Server/DC instance, not Atlassian Cloud.
---

# Confluence (Server/DC)

Read and write pages, attachments, and images on the self-hosted Confluence
instance — **not Atlassian Cloud**. Every cloud-shaped call fails here: there is
no `/api/v2/pages`, no Basic `-u email:api-token`, no ADF bodies.

The hostname is a secret, not a constant — this repo is public. It lives
encrypted in `secrets/ops-agent.yaml` (`ops_agent.confluence_base_url`) and is
materialized to `~/.config/confluence/base-url`; the `confluence-*` helpers
below already read it from there.

Two helpers own the boilerplate. Reach for them before hand-rolling `curl`:

| Need | Command |
| --- | --- |
| Any raw GET | `confluence-get '<path>'` |
| Read a page as text / XHTML / JSON | `confluence-page read <id> [--format storage\|json]` |
| List child pages | `confluence-page children <id>` |
| Create a page | `confluence-page create --space KEY --title T [--parent ID] --body-file F` |
| Replace a page body | `confluence-page update <id> --body-file F --expected-version N` |
| Retitle or re-parent | `confluence-page update <id> [--title T] [--parent ID]` |
| Upload / replace an attachment | `confluence-page attach <id> <file>...` |
| List attachments | `confluence-page attachments <id>` |
| Storage snippet for an image | `confluence-page embed <filename> [--alt TEXT] [--width N]` |

Both read credentials from `~/.config/confluence/{base-url,token}` (sops-managed;
see the sec-credentials skill) and keep the token out of argv. Run
`confluence-page --help` for full flags rather than guessing.

## The Model You Must Hold

A page is `{id, title, space, ancestors, body.storage, version}`. **A `PUT`
replaces the whole object.** Every field you omit is not "left alone" — it is
overwritten with whatever you sent. That single fact causes most of the damage
below, and it is why `confluence-page update` re-fetches the live page and
carries forward every field you did not explicitly change.

Bodies are *storage format*: XHTML with Confluence's `<ac:>` / `<ri:>` macro
namespaces. It is not Markdown and not HTML you can invent freely.

## Safe update workflow

Read the page before preparing its replacement. Body updates require
`--expected-version N`, where N is the version from that original read. A stale
version is rejected before writing; read the latest page and reconcile edits
before retrying. Substituting a newer number onto the same stale draft can lose
another editor's changes. Metadata-only edits preserve the live body and may
optionally assert a version. Empty or whitespace-only bodies are rejected.

The outgoing version is current + 1. The server still rejects a concurrent edit
after the check with `409`; writes are not automatically retried. `--minor`
suppresses watcher notifications for editorial changes.

Attachment discovery and listings follow all result pages. Uploads refresh the
name-to-ID lookup after each success, so repeated basenames in one invocation
update the attachment just created. `children --limit` is a positive page size,
not a total-result cap.

HTTP errors include status and method plus bounded, sanitized JSON API messages
when available. Raw HTML, malformed bodies, and credentials are not echoed.
Read back a changed page and compare attachment bytes when content matters;
a successful response alone is insufficient verification.

## Recipes and troubleshooting

- [Page workflows](references/page-workflows.md): saved-version body updates,
  image upload/embed, deletion, and read-back verification. Keep payloads in the
  agent cache, not inline shell arguments or tracked repository artifacts.
- [Server/DC pitfalls](references/server-dc-pitfalls.md): whole-body replacement,
  version conflicts, re-parenting, attachment replacement, XSRF headers, media
  types, error parsing, API roots, and transient connection failures.

## Related

- [sec-credentials](../sec-credentials/SKILL.md): token lookup and precedence.
- [ops-jira-integration](../ops-jira-integration/SKILL.md): Jira ticket operations.
- [shell-pitfalls](../shell-pitfalls/SKILL.md): quoting and file-backed payloads.
