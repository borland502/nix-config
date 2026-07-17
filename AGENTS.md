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
  `skills/` deploys globally (always-on); `skills-stack/` is opt-in per
  project via `task skills:enable SKILL=<name> DIR=<project>`
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

- Format Nix with `alejandra` (`task fmt`); lint with `statix`/`deadnix`.
- Never edit rendered instruction copies by hand
  (`chezmoi/dot_config/claude/CLAUDE.md`, `.github/copilot-instructions.md`,
  `chezmoi/dot_config/github-copilot/**`, `chezmoi/dot_config/Code/**`) —
  edit `agent-defaults.md` and regenerate.
- `agent-defaults.md` is budgeted (`task check:instruction-size`); put
  reference material in `agent-reference.md`, not the always-on prefix.
- Skills and agents must stay model-agnostic: use tier aliases
  (`fable`/`sonnet`/`haiku`) in `model:` frontmatter, never versioned model
  IDs (`task check:model-agnostic` enforces this on ai-tools/). The single
  sanctioned pin point is the `ANTHROPIC_DEFAULT_*_MODEL` env block in
  `chezmoi/dot_claude/settings.json`, which resolves each alias to the
  latest model of its tier — bump those IDs when new models ship. Copilot
  biases to OpenAI's top tier: common.nix resolves sol > terra > best
  available gpt-5.x slug from the installed CLI's own model list (auto only
  as safety net), re-resolving on every switch so sol/terra/luna are adopted
  as GitHub ships them.
- Secrets go through sops — use the sec-sops-encrypt skill.
- For build/switch failures use the ops-nix-pitfalls skill; for chezmoi
  behavior the ops-chezmoi skill; token-cost levers are documented in
  `docs/agent-token-cost-levers.md`.
- Markdown is linted (`task lint:md`, 120-char lines via `.markdownlint.yaml`
  where it applies); YAML via `yamllint`.
