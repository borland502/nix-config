# Agent token-cost levers

Reference for keeping Claude Code and GitHub Copilot CLI token/credit usage
down. Deliberately a standalone doc — **not** part of `agent-defaults.md`,
because anything added there loads into every session's prompt and would cost
tokens to save tokens.

## Billing context

- **Claude Code** — token-metered. The system prompt + tool defs +
  instruction files (`CLAUDE.md`) form a cacheable prefix; a stable prefix hit
  within the cache TTL bills at a fraction of the normal input rate.
- **GitHub Copilot CLI** — usage-based billing (AI Credits) since June 1 2026.
  Token-metered per model, with input / **cached input** / output priced
  separately; cached input is heavily discounted (~10% of input). Code
  completions / next-edit suggestions are not billed. So the same
  stable-prefix discipline that helps Claude now also lowers the Copilot bill.

## Levers codified in this repo

| Lever | Mechanism | Status |
|---|---|---|
| Stable, single-source instruction files | `agent-defaults.md` → generated copies; `generate`/`check:agent-instructions`/`check:copilot-instructions` gates prevent drift, keeping the cached prefix stable | active |
| Instruction-size budget | `task check:instruction-size` (in the `lint:nix` pre-commit chain) fails if `agent-defaults.md` exceeds the line/byte budget | active |
| Lean skill set | fewer skills = smaller skill listing (Claude) / fewer bridged prompt files (Copilot); `cleanupOrphanedSkills` removes deployed orphans | active |
| Core/stack skill split | only `ai-tools/skills/` deploys globally; stack skills live in `ai-tools/skills-stack/` and are linked per project via `task skills:enable` (pattern: khaneliman/khanelinix) | active |
| Rules/reference split | `agent-defaults.md` carries behavioral rules only; catalogs and paths moved to `agent-reference.md`, read on demand (pattern: khanelinix tiny-root) | active |
| Repo-level `AGENTS.md` | layout map + task targets at the repo root, so sessions here don't re-explore the repo (uncached, full-price tokens) each time | active |
| Scheduled update PRs | `.github/workflows/update-flake.yml` bumps `flake.lock` weekly via PR, removing routine update sessions entirely (pattern: budimanjojo Renovate / wimpysworld DS automation) | active |
| Copilot default model | `ensureCopilotSettings` sets `model: "auto"` in `~/.config/copilot/settings.json` | active |
| Lean Copilot MCP set | managed `copilot/mcp-config.json` (empty by default); servers added deliberately in `common.nix`, not accumulated via `/mcp add` | active |

## Levers that are not codifiable here

- **GitHub budgets, spend-blocking, model policies** — account/org dashboard,
  not nix-managed.
- **Session discipline** — reuse a session and avoid churning the prompt prefix
  mid-session so the cache discount keeps applying; pick a cheaper model for
  simple tasks. Operational, not config.

## Visibility

- **Claude:** `claude-cache-stats` (SessionEnd hook) reports prompt-cache hit
  rate from transcripts.
- **Copilot:** no equivalent — `events.jsonl` exposes no token/cache counts;
  usage is visible only in the GitHub billing dashboard.

## Notes

- `auto` routes Copilot to a capability-appropriate model, optimizing for fit,
  not strictly lowest cost. For hard cost-minimization, pin a cheap model
  instead (also settable in `ensureCopilotSettings`).
- The managed `copilot/mcp-config.json` is read-only (a nix-store symlink), so
  add MCP servers by editing `common.nix`, not with interactive `/mcp add`.
