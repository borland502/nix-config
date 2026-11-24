# nix-config repo guide

One flake managing NixOS (`linux`), NixOS-WSL (`wsl`), and macOS (`darwin`)
plus a chezmoi layer for dotfiles and non-Nix hosts (Windows). Drive all
workflows through `task` — do not hand-assemble `nixos-rebuild` /
`darwin-rebuild` / `home-manager` invocations.

## Layout

- `flake.nix` — inputs (nixpkgs, home-manager, nix-darwin, NixOS-WSL,
  sops-nix, stylix, plasma-manager) and per-host outputs
- `hosts/{darwin,linux,wsl}/` — system-level host definitions
- `home-manager/` — shared user config; `common.nix` is the package set and
  agent-tooling deployment; `lib/agent-instructions.nix` renders agent files
- `chezmoi/` — chezmoi-managed dotfiles for all platforms;
  `dot_config/instructions/agent-defaults.md` is the single source for the
  always-on agent prefix (reference detail: `agent-reference.md` beside it)
- `ai-tools/` — skills + agents (Claude plugin marketplace).
  `skills/` deploys globally (always-on); a skill only one project needs
  belongs in that project's own `.claude/skills/`, not here
- `secrets/` — SOPS-encrypted (age); never commit plaintext secrets
- `scripts/`, `taskfile.yaml` — automation; `docs/` — design notes

## Key tasks

- `task switch` / `task home-switch` — build + activate (auto-detects host;
  runs chezmoi apply, fmt, and instruction regeneration first)
- `task build` / `task dry-build` / `task check` — build or validate only
- `task lint` / `task fmt:all` — all linters / all formatters
  (`task lint:nix` is the pre-commit chain)
- `task generate:agent-instructions` — REQUIRED after editing
  `agent-defaults.md`; commit the regenerated copies together with the source
- `task upgrade` — flake update + switch (CI also opens weekly update PRs)

## Rules

- On macOS, run `task switch`, `task upgrade`, `task home-switch`, rollback,
  and other activation or app-modifying commands inside Apple Terminal.app.
  This uses Terminal's macOS app-management permissions and interactive sudo.
  Preserve direnv and the repository directory, for example
  `direnv exec <root> task --dir <root> switch`. An agent PTY is not Terminal.app;
  confirm the command's actual completion there before reporting success.
- Format Nix with `alejandra` (`task fmt`); lint with `statix`/`deadnix`.
- Never edit rendered instruction copies by hand
  (`chezmoi/dot_config/claude/CLAUDE.md`, `.github/copilot-instructions.md`,
  `chezmoi/dot_config/github-copilot/**`, `chezmoi/dot_config/Code/**`) —
  edit `agent-defaults.md` and regenerate.
- `agent-defaults.md` is budgeted (`task check:instruction-size`); put
  reference material in `agent-reference.md`, not the always-on prefix.
- Skills and agents must stay model-agnostic: use tier aliases
  (`opus`/`sonnet`/`haiku`) in `model:` frontmatter, never versioned model
  IDs (`task check:model-agnostic` enforces this on ai-tools/). Tiers float
  rather than pin, so they never age into legacy models: Claude's aliases
  resolve natively to the newest model of each tier (no
  `ANTHROPIC_DEFAULT_*_MODEL` pins; `ensureClaudeHook` removes any), and
  Copilot/Codex tiers are model *families* (`sol`/`terra`/`luna`) in
  `home-manager/lib/model-tiers.nix`, resolved at activation by
  `scripts/resolve-model-tiers.py` to the newest slug in Codex's live catalog,
  never below the floor slugs there. The only versioned IDs are those floors:
  raise them when activation warns they lag the catalog. The session default
  is the **high** tier on every harness (Claude `opus`, Copilot and a fresh
  Codex config the newest `sol`); subagent dispatch still picks the tier per
  role from the role→tier map in agent-reference.md § Model Tiers.
  (Copilot's `help config` model list lags the backend, so don't gate on it.)
- Secrets go through sops — use the sec-sops-encrypt skill.
- For build/switch failures use the ops-nix-pitfalls skill; for chezmoi
  behavior the ops-chezmoi skill; token-cost levers are documented in
  `docs/agent-token-cost-levers.md`.
- Markdown is linted (`task lint:md`); config is `.markdownlint.json` — note
  MD013 is off, so there is no line-length limit. YAML via `yamllint`.
