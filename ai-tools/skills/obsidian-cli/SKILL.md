---
name: obsidian-cli
description: Interact with Obsidian vaults using the Obsidian CLI to read, create, search, and manage notes, tasks, properties, and more. Also supports plugin and theme development. Use when the user asks to interact with their Obsidian vault, manage notes, search vault content, or develop and debug Obsidian plugins and themes.
origin: kepano/obsidian-skills
---

# Obsidian CLI

Use the `obsidian` CLI to interact with a running Obsidian instance. Requires Obsidian to be open.

Run `obsidian help` to see all available commands (always up to date). Full docs: https://help.obsidian.md/cli

## Syntax

**Parameters** take a value with `=`. Quote values with spaces:

```bash
obsidian create name="My Note" content="Hello world"
```

**Flags** are boolean switches with no value:

```bash
obsidian create name="My Note" silent overwrite
```

Use `\n` for newline and `\t` for tab in multiline content.

## File Targeting

Many commands accept `file` or `path`:
- `file=<name>` — resolves like a wikilink (name only, no path or extension needed)
- `path=<path>` — exact path from vault root, e.g. `folder/note.md`

Without either, the active file is used.

## Vault Targeting

Use `vault=<name>` as the first parameter to target a specific vault (default: most recently focused):

```bash
obsidian vault="My Vault" search query="test"
```

## Common Patterns

```bash
obsidian read file="My Note"
obsidian create name="New Note" content="# Hello" template="Template" silent
obsidian append file="My Note" content="New line"
obsidian search query="search term" limit=10
obsidian daily:read
obsidian daily:append content="- [ ] New task"
obsidian property:set name="status" value="done" file="My Note"
obsidian tasks daily todo
obsidian tags sort=count counts
obsidian backlinks file="My Note"
```

Use `--copy` to copy output to clipboard. Use `silent` to prevent files from opening. Use `total` on list commands for a count.

## Plugin Development Workflow

After making code changes to a plugin or theme:

1. **Reload** the plugin:
   ```bash
   obsidian plugin:reload id=my-plugin
   ```
2. **Check for errors**:
   ```bash
   obsidian dev:errors
   ```
3. **Verify visually**:
   ```bash
   obsidian dev:screenshot path=screenshot.png
   obsidian dev:dom selector=".workspace-leaf" text
   ```
4. **Check console output**:
   ```bash
   obsidian dev:console level=error
   ```

### Additional Developer Commands

```bash
obsidian eval code="app.vault.getFiles().length"   # Run JS in app context
obsidian dev:css selector=".workspace-leaf" prop=background-color
obsidian dev:mobile on                              # Toggle mobile emulation
```
