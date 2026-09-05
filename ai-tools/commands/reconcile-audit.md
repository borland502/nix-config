---
description: Reconcile ai-tools/skills & agents against the chezmoi 720h upstream pull — audit local drift by default, re-sync only when asked. Report-only unless the user approves a write.
---

Reconcile this repo's vendored AI tooling against its upstream sources. **The
default run is report-only: make no edits, no commits, no syncs.** Only move past
the audit when the user explicitly asks for a re-sync, and only after the audit
has said what a re-sync would overwrite.

The goal is deliberate propagation, not automatic: surface what changed, decide,
then act.

## Layout

Local source of truth (deployed to `~/.config/{claude,copilot}` by Home Manager):

```text
ai-tools/
  .claude-plugin/{marketplace.json,plugin.json}
  skills/<name>/
  agents/<name>.agent.md
  commands/<name>.md
```

Upstream sources — read-only, refreshed by chezmoi externals every ~720h; see
`chezmoi/.chezmoiexternal.toml.tmpl`:

```text
~/.local/src/ai-tools/
  anthropic-skills/         (mixed license — proprietary doc skills NOT ingested;
                             loaded at runtime via the upstream marketplace)
  superpowers/              (MIT, obra)
  everything-claude-code/   (MIT, ECC)
  webmaton/                 (MIT, AppAutomaton)
  angular-skills/           (MIT, Google LLC — skills live at the repo ROOT,
                             e.g. angular-developer/SKILL.md, not under skills/;
                             layout changed upstream ~2026-07)
```

`anthropic-skills` is registered as a separate Claude Code marketplace by
`home-manager/common.nix`; reconciliation covers only content actually copied
into `ai-tools/`.

## Audit (the default run)

1. Confirm the working directory:
   `git -C /Users/42245/.config/nix rev-parse --show-toplevel`.
2. Refresh the checkouts:
   `chezmoi apply --refresh-externals ~/.local/src/ai-tools`. Each external is
   pulled `--ff-only`; if one has diverged the pull aborts — investigate rather
   than forcing it.
3. Locate each skill upstream: `fd -t d "<skill>" ~/.local/src/ai-tools/*/skills/`.
   If two repos export the same name, decide which is authoritative before
   touching the local copy.
4. Diff every ingested skill and classify the hunks:

   ```bash
   diff -ruN ai-tools/skills/<skill>/ ~/.local/src/ai-tools/<repo>/skills/<skill>/
   ```

   - **Upstream-only** → safe to apply.
   - **Local-only** → the changes a blind re-ingest would silently destroy. Stop
     and ask before overwriting.
   - **Both sides** → conflict; resolve by hand, preserving the local intent.

5. Sweep for divergence nobody planned to re-sync:

   ```bash
   for skill in ai-tools/skills/*/; do
     name=$(basename "$skill")
     for repo in ~/.local/src/ai-tools/*/skills/"$name"; do
       [ -d "$repo" ] || continue
       diff -rq "$skill" "$repo" >/dev/null 2>&1 ||
         echo "DIVERGED: $name (vs $(basename $(dirname $(dirname "$repo"))))"
     done
   done
   ```

   Each `DIVERGED` line is a candidate to upstream as a PR or to record so the
   next reconciliation preserves it.

Use `git`, `diff`, `rg`, `fd` — not `grep`/`find`.

Output a concise digest:

- **Drifted (local edits at risk):** path → one-line summary of the local change
- **Local-only (safe):** names
- **Upstream-only (not ingested):** names
- **Action needed?** yes/no + the single next command to run

If nothing has drifted, say so in one line and stop.

## Re-sync (only on explicit approval)

Re-pulling is always safe; re-ingesting is destructive. Proceed only once the
audit shows no local divergence, or the user has accepted losing it.

1. Apply the resolved version:

   ```bash
   # upstream wins outright
   cp -R ~/.local/src/ai-tools/<repo>/skills/<skill>/. ai-tools/skills/<skill>/
   # or patch selectively, reviewing each hunk
   diff -u ai-tools/skills/<skill>/SKILL.md \
           ~/.local/src/ai-tools/<repo>/skills/<skill>/SKILL.md
   ```

2. Rewrite namespace cross-references. Upstream skills cite their own
   marketplace prefix (`superpowers:executing-plans`); inside this marketplace
   they must be `nix-config-tools:` to resolve:

   ```bash
   rg -l 'superpowers:|<other-prefix>:' ai-tools/skills/<skill>/ | while read -r f; do
     sd '<upstream-prefix>:' 'nix-config-tools:' "$f"
   done
   rg '(superpowers|anthropic|webmaton|angular):[a-z-]+' ai-tools/skills/<skill>/ || echo clean
   ```

3. Rewrite upstream-relative paths: tracked spec/plan paths such as
   `docs/**/plans/` or `docs/**/specs/` → `~/.cache/copilot/`; `~/.claude/…` /
   `~/.copilot/…` → `$CLAUDE_CONFIG_DIR/…` / `$COPILOT_HOME/…`.

4. Validate: `task fmt`, `task lint:nix`, `task home-build`. A clean home-build
   confirms `home-manager/common.nix` still resolves the new content; then open a
   session and confirm the skill loads via `/plugins`.

## Ask before overwriting when

- The local file is newer than the upstream commit and the content differs.
- `git log --follow ai-tools/skills/<skill>/` shows a project-specific commit,
  not just the original ingest.
- The frontmatter `origin` field was changed locally.
- A file exists locally that upstream does not have.

State the divergence concretely — "local SKILL.md adds 12 lines under '## Project
Layout References' that aren't upstream — keep, drop, or upstream?" — rather than
asking in general terms.

## Hard rules

- The proprietary `anthropic-skills/document-skills` plugin (`docx`, `pdf`,
  `pptx`, `xlsx`) must **never** be copied into `ai-tools/skills/`. It is loaded
  only at runtime through the upstream marketplace registration in
  `home-manager/common.nix`. Re-pulling is fine; re-ingesting is a license
  violation.
- Upstream `origin:` frontmatter is preserved verbatim for traceability — never
  strip it. A skill whose content is folded into an agent or command carries its
  attribution along with it.
- `ai-tools/skills/` is the only globally deployed set, and every skill in it
  spends description tokens in every session. Ingesting is a cost decision, not
  just a copy: if a skill would serve one project, it belongs in that project's
  own `.claude/skills/`.
