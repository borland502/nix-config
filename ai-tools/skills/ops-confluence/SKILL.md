---
name: ops-confluence
description: Use when reading or writing Confluence pages, uploading or replacing attachments, embedding images or diagrams in a page, re-parenting or moving a page, or debugging a Confluence REST failure (HTTP 400 "same file name", 404 on /move or /api/v2/pages, a blanked page body, a jq parse error on an HTML error body). Covers the self-hosted Server/DC instance, not Atlassian Cloud.
---

# Confluence (Server/DC)

Read and write pages, attachments, and images on the self-hosted Confluence at
`confluenceent.cms.gov` — **not Atlassian Cloud**. Every cloud-shaped call fails
here: there is no `/api/v2/pages`, no Basic `-u email:api-token`, no ADF bodies.

Two helpers own the boilerplate. Reach for them before hand-rolling `curl`:

| Need | Command |
| --- | --- |
| Any raw GET | `confluence-get '<path>'` |
| Read a page as text / XHTML / JSON | `confluence-page read <id> [--format storage\|json]` |
| List child pages | `confluence-page children <id>` |
| Create a page | `confluence-page create --space KEY --title T [--parent ID] --body-file F` |
| Update, retitle, or re-parent | `confluence-page update <id> [--body-file F] [--title T] [--parent ID]` |
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

## Pitfalls

Each of these has actually happened on this instance.

### An update without a body wipes the page

`PUT` with no `body` blanks the content. Always re-fetch and send the current
body back unless you are deliberately replacing it. `confluence-page update`
does this for you — `--body-file` is optional precisely so that retitling and
re-parenting cannot destroy content.

### The version number must be exactly current + 1

Not the version you read five minutes ago — a concurrent edit moves it. Read the
version immediately before the write. A stale number is a `409`. `confluence-page`
always reads it fresh in the same call.

### `/move` does not exist — re-parent through `ancestors`

`PUT`/`POST` on `/rest/api/content/{id}/move/append/{target}` returns
`404 HTTP 404 Not Found` on this DC version, in an XML body that will also break
a `jq` pipe. Set `ancestors` in the normal update `PUT` instead:

```bash
confluence-page update 1380859735 --parent 1015307227
```

### Re-uploading an attachment name 400s

```text
HTTP 400 Cannot add a new attachment with same file name as an existing
attachment: mdpmdd-879-sequence.svg
```

`POST /child/attachment` only *creates*. To add a new version of an existing
file, `POST` to that attachment's own data endpoint,
`/child/attachment/{attachmentId}/data`. `confluence-page attach` looks up the
existing attachments by name and picks the right endpoint automatically, so the
same command both creates and updates.

### Uploads need the XSRF opt-out header

Multipart uploads without `X-Atlassian-Token: no-check` are rejected. (`nocheck`
also works; `no-check` is the current spelling.)

### Confluence sniffs media types, and gets SVG wrong

An SVG uploaded without an explicit `Content-Type` lands as
`application/octet-stream` and downloads instead of rendering. Send
`image/svg+xml` explicitly — `confluence-page` forces the type for `.svg`,
`.drawio`, and `.mmd`.

### Error bodies are HTML, so `jq` lies about the failure

A failing call often returns an HTML error page. Piping that to `jq` produces
`parse error: Invalid numeric literal`, which looks like a malformed-JSON bug
and hides the real 401/404. Both helpers report the status and body instead. If
you must use raw `curl`, capture `%{http_code}` and check it before parsing.

### The two base URLs are not symmetric

`~/.config/ops-agent/jira-base-url` **ends with** `/rest/api/2`;
`~/.config/confluence/base-url` is the **bare host**. A path shaped for Jira
404s against Confluence. The helpers own this composition — pass paths relative
to the REST root and do not prepend `/rest/api`.

### `Connection reset by peer` is usually the VPN

Transient and bursty. Retry 2–3 times with short backoff before re-diagnosing.

## Embedding an Image

Upload the file, then reference it by **filename** in the body:

```bash
confluence-page attach 1435323578 diagram.svg
confluence-page embed diagram.svg --alt "Runtime architecture" --width 900
```

which prints the snippet to paste into the storage body:

```xml
<ac:image ac:align="center" ac:width="900" ac:alt="Runtime architecture"><ri:attachment ri:filename="diagram.svg" /></ac:image>
```

The reference is by name, not id, so re-uploading a new version of the same
filename updates the rendered image everywhere it appears — no body edit needed.
That makes "attach with the same name" the right way to revise a diagram.

## Writing a Page Body

Build the storage XHTML in a file under `~/.cache/claude`, then pass
`--body-file`. Do not inline a large body into a shell command — the quoting
breaks and the payload lands in the logs.

```bash
cat > ~/.cache/claude/$(date +%F)-page-body.xhtml <<'EOF'
<h2>Summary</h2>
<p>Prose here.</p>
<ac:structured-macro ac:name="code"><ac:plain-text-body><![CDATA[
example --command
]]></ac:plain-text-body></ac:structured-macro>
EOF
confluence-page update 1435323578 --body-file ~/.cache/claude/$(date +%F)-page-body.xhtml \
  --message "Revise summary" --minor
```

`--minor` suppresses watcher notifications — use it for typo and formatting
passes, omit it when people should see the change.

## Deleting

Deliberately **not** a subcommand: an agent should have to construct this
consciously.

```bash
# 204 on success; the page goes to the space trash, not to permanent oblivion
curl -sS -X DELETE -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $(/bin/cat ~/.config/confluence/token)" \
  "$(/bin/cat ~/.config/confluence/base-url)/rest/api/content/PAGE_ID"
```

## Verifying a Write

Read back rather than trusting the response:

```bash
confluence-page read <id> | head -5           # title, version, parent
confluence-page attachments <id>              # names, versions, media types
```

For a diagram you replaced, compare the SHA-256 of the local file against the
downloaded attachment — a `200` alone does not prove the bytes landed.

## Related

- **sec-credentials** — where the token comes from and its lookup precedence
- **ops-jira-integration** — the Jira side; linking tickets to RFC pages
- **shell-pitfalls** — quoting traps when a payload does go through the shell
