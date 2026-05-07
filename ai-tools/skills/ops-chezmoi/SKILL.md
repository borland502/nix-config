---
name: ops-chezmoi
description: Use when adding/editing dotfiles managed by chezmoi in this repo, working with chezmoi externals (source repos under ~/.local/src), debugging template rendering, troubleshooting `chezmoi diff/apply` output, or when the user mentions chezmoi commands. Project-specific: chezmoi sources from <repo>/chezmoi via the state file at $XDG_STATE_HOME/chezmoi/nix-config-dir, and home-manager runs `chezmoi apply` automatically inside `task switch` / `task home-switch`.
---

# Chezmoi (this project)

Use this skill when working with the chezmoi-managed portion of this nix-config repo. The chezmoi source directory is `<repo>/chezmoi/`, NOT the default `~/.local/share/chezmoi`. Home Manager wires chezmoi to read from this repo via an activation script that points at the path recorded in `$XDG_STATE_HOME/chezmoi/nix-config-dir` (written by the `_record-nix-config-dir` task). That means chezmoi tracks the repo even if it's renamed or moved.

## Quick Reference

```bash
# Preview what would change
chezmoi diff

# Apply pending changes (Home Manager runs this automatically on task switch)
chezmoi apply

# Apply only a subset of the target tree (avoids interactive prompts on
# unrelated managed files like flameshot.ini)
chezmoi apply ~/.local/src/ai-tools

# Force-refresh externals beyond their refreshPeriod
chezmoi apply --refresh-externals

# Edit a managed file in-place (opens $EDITOR on the source file)
chezmoi edit ~/.config/some-tool/config.yaml

# Show what's managed and current source-vs-target status
chezmoi managed
chezmoi status

# Add a new file from $HOME into the source state
chezmoi add ~/.config/foo/bar.toml
```

Always pipe the command and its output into a timestamped file under `~/.cache/claude/`:

```bash
chezmoi diff 2>&1 | tee ~/.cache/claude/chezmoi-diff-$(date +%Y%m%d-%H%M%S).log
```

## Repo Layout

```
<repo>/
├── chezmoi/                                  source directory (overrides ~/.local/share/chezmoi)
│   ├── .chezmoiroot                          tells chezmoi to use ./chezmoi as its source
│   ├── .chezmoi.toml.tmpl                    init-time chezmoi config template
│   ├── .chezmoiexternal.toml.tmpl            git-repo externals (Go CLIs + ai-tools)
│   ├── .chezmoiignore.tmpl                   per-OS ignore rules
│   ├── dot_claude/                           → ~/.claude/
│   ├── dot_config/                           → ~/.config/
│   ├── dot_Documents/                        → ~/Documents/
│   ├── dot_local/                            → ~/.local/
│   ├── run_install-go-tools.sh.tmpl          run_ scripts execute on apply
│   └── run_onchange_deploy-vscode-instructions.ps1.tmpl
└── home-manager/common.nix                   contains the configureChezmoi
                                              activation hook
```

**Naming attributes** (see `references/source-state-attributes.md`):

- `dot_foo` → `.foo` in the target.
- `private_foo` → mode `0600`/`0700` in the target.
- `executable_foo` → executable bit set.
- `run_foo.sh.tmpl` → executed every `chezmoi apply`.
- `run_onchange_foo.ps1.tmpl` → executed when contents change.
- Suffix `.tmpl` → file is rendered through chezmoi's template engine.

## Externals

External git repos live under `~/.local/src/`. They are declared in [chezmoi/.chezmoiexternal.toml.tmpl](../../../chezmoi/.chezmoiexternal.toml.tmpl) and refreshed every `720h` (~1 month). To force a refresh sooner, run:

```bash
chezmoi apply --refresh-externals ~/.local/src
```

Two groups of externals are managed:

1. **Go CLI sources** — `wordgen`, `gopwgen`, `go-sea`. Built into `~/.local/bin` by `chezmoi/run_install-go-tools.sh.tmpl` on every apply.
2. **AI-tools sources** — `anthropic-skills`, `superpowers`, `everything-claude-code`, `webmaton`, `angular-skills`. Read by the [reconciliation](../reconciliation/SKILL.md) skill when re-syncing `ai-tools/skills/`. The Anthropic checkout is also registered as a separate Claude Code marketplace by [home-manager/common.nix](../../../home-manager/common.nix).

See `references/chezmoiexternal.md` for the full schema (all 25+ entry fields).

## Templates

`.tmpl` files use Go's `text/template` syntax with chezmoi additions. Conditionals on OS, hostname, or arch are common:

```toml
{{- if ne .chezmoi.os "windows" }}
[".local/src/wordgen"]
    type = "git-repo"
    url = "https://github.com/borland502/wordgen.git"
    refreshPeriod = "720h"
{{- end }}
```

Useful template data (run `chezmoi data` to dump the full set):

- `.chezmoi.os` — `linux`, `darwin`, `windows`
- `.chezmoi.arch` — `amd64`, `arm64`
- `.chezmoi.hostname`
- `.chezmoi.homeDir`
- `.chezmoi.username`

To debug a template without applying:

```bash
chezmoi execute-template '{{ .chezmoi.os }}-{{ .chezmoi.arch }}'
chezmoi cat ~/.config/some-templated-file
```

## SOPS / Age Encryption

This repo encrypts secrets with `age` (NOT chezmoi's built-in encryption — sops-nix manages decryption at activation time). Chezmoi's role is only to ferry the configured age identity files into place. See the [sec-sops-encrypt](../sec-sops-encrypt/SKILL.md) skill for the secrets workflow itself.

Chezmoi's age awareness is wired up by the `configureChezmoi` activation hook in [home-manager/common.nix](../../../home-manager/common.nix) — it writes `~/.config/chezmoi/chezmoi.toml` with the `age.identity` set to `~/.config/sops/age/keys.txt` when that key file is present.

## Common Tasks

### Add a new external repo

1. Edit [chezmoi/.chezmoiexternal.toml.tmpl](../../../chezmoi/.chezmoiexternal.toml.tmpl) and add a new entry:
   ```toml
   [".local/src/<name>"]
       type = "git-repo"
       url = "https://github.com/<org>/<repo>.git"
       refreshPeriod = "720h"
       [".local/src/<name>".pull]
           args = ["--ff-only"]
   ```
2. Run `chezmoi diff` to confirm only the expected change is pending.
3. Run `chezmoi apply --refresh-externals ~/.local/src/<name>` to clone immediately. Scoping the apply to the new path avoids prompts on unrelated managed files.
4. Verify: `ls ~/.local/src/<name>` and `cd ~/.local/src/<name> && git log -1`.

### Investigate a `chezmoi apply` prompt

When `chezmoi apply` (without flags) prompts about a file with `... has changed since chezmoi last wrote it?`, it's because the file in `$HOME` was modified out-of-band. Two clean responses:

- **Re-pull from source** (chezmoi wins): `chezmoi apply --force <path>`
- **Re-add into source** (in-place wins): `chezmoi add <path>` then commit.

Avoid `--force` blanket-wide; it overwrites every drifted file silently.

### Find what manages a given path

```bash
chezmoi source-path ~/.config/foo/bar.toml      # source file backing this target
chezmoi target-path chezmoi/dot_config/foo/bar.toml  # target file produced by this source
```

### Re-init after moving the repo

If the repo path changes, the activation hook in `common.nix` re-points chezmoi automatically *after* the next `task switch`. Until then, run `task chezmoi-init` (defined in [taskfile.yaml](../../../taskfile.yaml)) to update the chezmoi source pointer manually:

```bash
task chezmoi-init
task chezmoi-apply
```

## References

- **`references/command-overview.md`** — the chezmoi.io user-guide command overview, copied for offline use.
- **`references/reference-index.md`** — top-level index of every chezmoi reference page (commands, templates, special files, etc.) — use to know what upstream page to fetch when this skill doesn't cover something.
- **`references/chezmoiexternal.md`** — the `.chezmoiexternal.<format>` reference. Every field of every external-entry type.
- **`references/source-state-attributes.md`** — the file-naming attribute reference (`dot_`, `private_`, `executable_`, `run_`, `onchange_`, `.tmpl`, etc.).

For anything not covered here, the canonical doc is [chezmoi.io](https://www.chezmoi.io/). Use the upstream pages, then capture the relevant section into a new file under `references/` if it's likely to be needed offline.

## Notes

- This project's chezmoi source is `<repo>/chezmoi/`, not the default `~/.local/share/chezmoi`. The override is wired by `.chezmoiroot` plus the `configureChezmoi` activation hook.
- `task switch` / `task home-switch` already runs `chezmoi apply` via the `_chezmoi-ensure` dependency — manually running `chezmoi apply` is only needed for partial-tree applies or external refreshes between switches.
- chezmoi's own `update` command pulls the chezmoi *source repo* (this nix-config repo) and then applies. We don't use it because the repo is already managed by the user's normal git workflow; `task switch` is the integrated entrypoint.
