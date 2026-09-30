# Nix Configuration

Cross-platform personal configuration for NixOS, macOS, WSL, and native
Windows. Nix and Home Manager own packages and services; chezmoi deploys
dotfiles, encrypted project overlays, and agent tooling.

## Highlights

- Flake-based NixOS, nix-darwin, and standalone Home Manager configurations
- One `task` interface for builds, activation, updates, formatting, and checks
- Shared shell, Git, editor, terminal, desktop, and development-tool defaults
- SOPS/age secrets and age-encrypted chezmoi files
- Claude, Codex, and GitHub Copilot instructions generated from one source
- Reusable skills plus token-lean operational helpers and cache diagnostics
- Windows bootstrap through Scoop and chezmoi when Nix is unavailable

## Quick start

Clone the repository and enter its dev shell:

```bash
git clone https://github.com/borland502/nix-config.git ~/.config/nix
cd ~/.config/nix
direnv allow
```

The `.envrc` loads the flake environment. Non-interactive tools must use
`direnv exec ~/.config/nix <command>`; changing the working directory alone
does not load it.

### Linux and WSL

```bash
nix develop
task home-switch        # Home Manager only
task switch             # host-aware system activation
```

For a new WSL installation, use the repository bootstrap task first:

```bash
task wsl-bootstrap-windows
task wsl
```

### macOS

Install Nix, then:

```bash
nix develop
task switch             # auto-detects darwin
```

### Native Windows

```powershell
task windows-bootstrap
task chezmoi-init
task chezmoi-apply
```

### Secrets bootstrap

Install the age identity at `~/.config/sops/age/keys.txt` before activating a
host that consumes encrypted secrets. Never commit the identity. See
`.sops.yaml` for encrypted-file policy.

## Everyday commands

```bash
task build              # build without activation
task switch             # build and activate the detected host
task home-switch        # activate Home Manager only
task check              # flake evaluation and checks

task fmt                # Nix formatting
task fmt:all            # all configured formatters
task lint               # all linters and policy checks

task update             # update flake inputs
task upgrade            # update, activate, and refresh agent CLIs
task agents:update      # refresh only off-nixpkgs agent CLIs
task gc                 # remove old generations
task optimize           # deduplicate the Nix store
```

Override platform detection with `HOST=<target>`, for example
`task switch HOST=linux`. Short aliases include `task linux`, `task darwin`,
and `task wsl`.

`task switch` takes a safety snapshot when supported, builds before activation,
applies Home Manager, records this repository as the chezmoi source, and runs
`chezmoi apply`. That last step keeps dotfiles and generated agent configuration
in sync with the activated Nix generation.

## Repository layout

| Path | Purpose |
| --- | --- |
| `flake.nix` | Inputs and host outputs |
| `nixos/` | NixOS hosts and hardware configuration |
| `darwin/` | nix-darwin hosts |
| `home-manager/` | Shared profiles, modules, packages, and editor settings |
| `chezmoi/` | Dotfile source tree and encrypted project overlays |
| `secrets/` | SOPS-encrypted structured secrets |
| `ai-tools/` | Shared skills, agents, hooks, and automation scripts |
| `pkgs/` | Repository-owned packages and tools |
| `taskfiles/` | Quality and deployment task groups |
| `tests/` | Fixture-based helper tests |

## Chezmoi workflow

The source directory is `chezmoi/`. Home Manager records its path in the
chezmoi state file, and switch tasks apply it automatically.

```bash
task chezmoi-init
task chezmoi-status
task chezmoi-diff
task chezmoi-add FILE=~/.somerc
task chezmoi-edit FILE=~/.somerc
task chezmoi-apply
```

Use normal chezmoi templates for platform-specific files. Sensitive or
organization-specific project material belongs under `chezmoi/Development/**`
as `encrypted_*` age ciphertext. Public documentation may name the materialized
path but must not repeat private endpoints, repository layouts, or values.

## Secrets

Structured secrets live in `secrets/*.yaml` and are decrypted by the Home
Manager SOPS module. Secret-bearing dotfiles use chezmoi age encryption.

```bash
sops secrets/example.yaml
task check:secret-hygiene
task lint:secrets
```

The secret-hygiene check rejects plaintext internal endpoints, credentials,
and unencrypted work-repository files before commit.

## Operational helpers

Chezmoi deploys helpers to `~/.local/bin`. Detailed usage lives in
`~/.config/instructions/agent-reference.md`.

| Helper | Purpose |
| --- | --- |
| `cache-scan` | Summarize retained agent sessions and artifacts |
| `gh-pr-threads` | List unresolved or filtered PR review threads |
| `gh-graphql` | Run file-backed GraphQL and jq pipelines |
| `gh-run-logs` | Persist Actions logs in the retained agent cache |
| `monitor-gh-run` | Poll Actions without ad-hoc sleep loops |
| `aws-stack-triage` | Read-only stack summary, nesting, and failed events |
| `git-worktree-audit` | Read-only merged, unmerged, detached, stale, and dirty inventory |
| `kac` | Source and refresh temporary AWS credentials |
| `jira-get` / `confluence-get` | Authenticated reads with response validation |
| `confluence-page` | Guarded Confluence page and attachment operations |

Project-only helpers and skills are deployed from encrypted chezmoi sources.
They can compose these public primitives without exposing project topology in
this repository.

### Cache audits

Agent hooks write a canonical per-session stream under `~/.cache/<agent>`.
Routine reads are intentionally compact:

```bash
cache-scan                         # recent sessions, failures, and artifacts
cache-scan --session <id>          # search all retained history for one id
cache-scan --transcript --limit 5  # native tool failures and decisions
cache-scan --classify --days 30    # heuristic failure families
cache-scan --audit                 # 30-day remediation view
```

`--audit` keeps three evidence classes separate: actual native tool errors,
heuristic failure signals, and recursively discovered script-artifact families.
Dependency and build trees are excluded so repeated one-off automation is
visible without counting vendored code.

## AI tooling

`chezmoi/dot_config/instructions/agent-defaults.md` is the concise source for
always-on behavior. `agent-reference.md` holds details loaded only on demand.
Generated Claude and Copilot instruction files must not be edited by hand.

```bash
task generate:agent-instructions
task check:agent-instructions
task check:copilot-instructions
task check:instruction-size
task check:model-agnostic
```

Shared skills live under `ai-tools/skills/` and are linked into each supported
agent's discovery path. Codex receives individual skill links rather than a
linked parent directory so its discovery boundary remains explicit.

Agent CLIs that move faster than nixpkgs are installed by chezmoi's onchange
installer and refreshed by `task agents:update`. They are intentionally not
pinned in the flake.

## Formatting and validation

```bash
task fmt:all
task lint
task check
```

Focused checks are available when iterating:

```bash
task lint:nix
task lint:md
task lint:sh
task lint:py
task lint:yaml
task lint:toml
task check:secret-hygiene
```

Install the tracked pre-commit hooks once per clone:

```bash
task hooks:install
```

The hooks enforce formatting, generated-instruction consistency, instruction
size, model-agnostic skill metadata, and public-repository secret hygiene.

## Maintenance

```bash
task update && task switch
task upgrade
task gc
task optimize
```

Before changing a host or module, prefer the smallest build that exercises it.
Use `task build` for evaluation-only work and activate only after the build
passes. Repository-owned packages expose their own namespaced `task` checks.

## License and credits

The configuration is personal and public; reuse it selectively rather than as
a drop-in host configuration. Third-party skill origins and licenses are
recorded in each skill's frontmatter and upstream notices.
