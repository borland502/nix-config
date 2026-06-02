---
description: Audit ai-tools/skills & agents for local drift vs upstream after the chezmoi 720h external pull (flow-reconciliation). Report-only — never overwrites.
---

Run a reconciliation audit of this repo's vendored AI tooling. Safe to run
unattended: **report only — make no edits, no commits, no syncs.**

Follow the `flow-reconciliation` skill. Concretely:

1. Working dir is the nix-config repo. Confirm with
   `git -C /Users/42245/.config/nix rev-parse --show-toplevel`.
2. Identify the upstream sources for `ai-tools/skills/` and `ai-tools/agents/`
   (chezmoi externals under `~/.local/src/ai-tools/`, refreshed every ~720h).
3. For each locally-present skill/agent that also exists upstream, diff to
   surface **local-only divergence** that a re-sync would silently overwrite.
   Use `git`, `diff`, `rg`, `fd` — not `grep`/`find`.
4. Note skills/agents that are local-only (no upstream) and upstream items not
   yet ingested.

Output a concise digest:

- **Drifted (local edits at risk):** path → one-line summary of the local change
- **Local-only (safe):** names
- **Upstream-only (not ingested):** names
- **Action needed?** yes/no + the single next command to run

Do not modify files. If nothing has drifted, say so in one line.
