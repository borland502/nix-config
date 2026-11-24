# Confluence page workflows

## Embedding an image

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

Save the original page and its version before editing. Build the replacement
storage XHTML in the agent cache, preserving the page content you intend to
keep, then pass `--body-file` and that original `--expected-version`. Keep large
bodies in files rather than inline shell arguments.

```bash
page_id=123456
page_snapshot=~/.cache/codex/$(date +%F)-page-before.json
page_body=~/.cache/codex/$(date +%F)-page-body.xhtml
confluence-page read "$page_id" --format json > "$page_snapshot"
page_version=$(jq -er '.version.number' "$page_snapshot")
jq -erj '.body.storage.value | select(type == "string")' "$page_snapshot" > "$page_body"
```

Edit `page_body` to make the intended changes while retaining the content and
macros that should remain. Review the complete draft before publishing it.
After editing, use the version from the saved snapshot:

```bash
confluence-page update "$page_id" --body-file "$page_body" \
  --expected-version "$page_version" --message "Revise summary" --minor
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
