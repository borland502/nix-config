---
name: flow-reconciliation
description: Use when ingesting new skills/agents from upstream repos, refreshing already-ingested content after the chezmoi 720h external pull, or auditing whether local edits to ai-tools/skills/ have drifted from upstream. Surfaces local-only divergence so it isn't silently overwritten by a re-sync.
---

# Reconciliation

Use this skill when reconciling `ai-tools/skills/` and `ai-tools/agents/` against the chezmoi-managed upstream sources under `~/.local/src/ai-tools/`. The goal is **deliberate**, not automatic, propagation: surface what changed, decide what to do, then act.

> **Note:** stack-specific skills (language/framework patterns) live in `ai-tools/skills-stack/`, not `ai-tools/skills/` — they are opt-in per project (`task skills:enable`) rather than always-on. Every `ai-tools/skills/` path or loop in this document applies equally to `ai-tools/skills-stack/`; sweep both directories when reconciling.

## When To Use

- Ingesting a new skill from one of the upstream repos for the first time.
- Re-syncing an already-ingested skill after `chezmoi update` refreshes the upstream checkout (default: every 720h ≈ 1 month).
- Auditing local divergence before `task upgrade` so a future ingest doesn't clobber a project-specific change.
- Investigating which upstream repo a skill came from (the `origin` frontmatter field is informational, not enforced).

## Layout

**Local source of truth** (deployed to `~/.config/{claude,copilot}` by Home Manager):
```
ai-tools/
  .claude-plugin/{marketplace.json,plugin.json}
  skills/<name>/
  agents/<name>.agent.md
```

**Upstream sources** (read-only, refreshed by chezmoi externals at 720h intervals; see [chezmoi/.chezmoiexternal.toml.tmpl](../../../chezmoi/.chezmoiexternal.toml.tmpl)):
```
~/.local/src/ai-tools/
  anthropic-skills/         (mixed license — proprietary doc skills NOT ingested; loaded via upstream marketplace)
  superpowers/              (MIT, obra)
  everything-claude-code/   (MIT, ECC)
  webmaton/                 (MIT, AppAutomaton)
  angular-skills/           (MIT, Google LLC)
```

`~/.local/src/ai-tools/anthropic-skills` is registered as a separate Claude Code marketplace by [home-manager/common.nix](../../../home-manager/common.nix); reconciliation here only covers content actually copied into `ai-tools/skills/`.

## Procedure

### 1. Refresh the upstream checkouts

```bash
chezmoi apply --refresh-externals ~/.local/src/ai-tools
```

This re-pulls each external (`--ff-only`). If the local working copy of an upstream has diverged for any reason, the pull aborts — investigate before proceeding.

### 2. Identify the upstream skill (or set of skills)

For each `<skill>` you intend to reconcile, locate it:

```bash
fd -t d "<skill>" ~/.local/src/ai-tools/*/skills/
```

If multiple repos export the same name, decide which is authoritative for this project before touching the local copy.

### 3. Diff local vs upstream

For an already-ingested skill:

```bash
diff -ruN ai-tools/skills/<skill>/ ~/.local/src/ai-tools/<repo>/skills/<skill>/
```

Classify each hunk:

- **Upstream-only changes** → safe to apply (`cp -R` over the local copy).
- **Local-only changes** → these are the "logical changes that would be ignored" if you blindly re-ingest. STOP and prompt the user before overwriting.
- **Both-side changes** → conflict. Resolve manually; preserve the project-specific intent.

### 4. Detect untracked local divergence

Even when no re-sync is planned, periodically run:

```bash
for skill in ai-tools/skills/*/; do
  name=$(basename "$skill")
  for repo in ~/.local/src/ai-tools/*/skills/"$name"; do
    [ -d "$repo" ] || continue
    if ! diff -rq "$skill" "$repo" >/dev/null 2>&1; then
      echo "DIVERGED: $name (vs $(basename $(dirname $(dirname "$repo"))))"
    fi
  done
done
```

Each `DIVERGED` line is a candidate for either upstreaming (open a PR to the source repo) or documenting in a NOTICE so future reconciliation knows to preserve it.

### 5. Apply the resolved version

```bash
# Pure upstream-wins re-sync (only after confirming no local divergence):
cp -R ~/.local/src/ai-tools/<repo>/skills/<skill>/. ai-tools/skills/<skill>/

# Or selective patching:
diff -u ai-tools/skills/<skill>/SKILL.md ~/.local/src/ai-tools/<repo>/skills/<skill>/SKILL.md \
  | review-and-apply-by-hand
```

### 6. Re-write namespace cross-references

Upstream skills use their own marketplace prefix in cross-skill references (e.g. `superpowers:executing-plans`). Inside this repo's marketplace they must be `nix-config-tools:` to resolve:

```bash
# After copying:
rg -l 'superpowers:|<other-prefix>:' ai-tools/skills/<skill>/ | while read -r f; do
  sd '<upstream-prefix>:' 'nix-config-tools:' "$f"
done
```

Verify nothing slipped through:

```bash
rg '(superpowers|anthropic|webmaton|angular):[a-z-]+' ai-tools/skills/<skill>/ || echo "clean"
```

### 7. Check for upstream-relative paths

Upstream skills sometimes reference paths under their own repo layout (e.g. `docs/superpowers/plans/`, `~/.claude/skills/`). Rewrite to project-relative paths or env-var paths:

- `docs/<repo>/plans/` → `docs/plans/`
- `~/.claude/...` / `~/.copilot/...` → `$CLAUDE_CONFIG_DIR/...` / `$COPILOT_HOME/...`

### 8. Validate

```bash
task fmt
task lint:nix
task home-build
```

A clean home-build confirms `home-manager/common.nix` still resolves the new content. Then run a Claude Code session and confirm the skill loads via `/plugins`.

## When To Prompt The User

Ask before overwriting if any of:

- Local file timestamp is newer than the upstream commit time and content differs.
- A `git log --follow ai-tools/skills/<skill>/` shows a project-specific commit (not just the original ingest).
- The frontmatter `origin` field has been changed locally.
- A new file exists locally that is not present upstream — e.g. a project-flavored `LAYOUT.md` appended for golang-patterns.

State the divergence concretely ("local SKILL.md adds 12 lines under '## Project Layout References' that aren't upstream — keep, drop, or upstream?") rather than asking generally.

## Re-Pulling vs. Re-Ingesting

- **Re-pull**: `chezmoi apply --refresh-externals` — updates `~/.local/src/ai-tools/<repo>` only. Always safe.
- **Re-ingest**: copying upstream files over `ai-tools/skills/<skill>/` — destructive. Only after Step 4 confirms no untracked local divergence, or after the user explicitly approves losing it.

## Notes

- Upstream `origin:` frontmatter is preserved verbatim for traceability — do not strip it.
- The proprietary `anthropic-skills/document-skills` plugin (`docx`, `pdf`, `pptx`, `xlsx`) must never be copied into `ai-tools/skills/`. It is only ever loaded at runtime via the upstream marketplace registration in [home-manager/common.nix](../../../home-manager/common.nix). Re-pulling is fine; re-ingesting is a license violation.
- For Go skills, the appended "Project Layout References" section (pointing at `golang-standards/project-layout` and `borland502/go-sea`) is a deliberate local addition. Preserve it across re-syncs.
