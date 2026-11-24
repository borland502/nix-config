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
- Reusable skills, capability-based model tiers, operational helpers, and cache diagnostics
- Claude hooks for shell guidance, Nix formatting, and Markdown lint feedback
- Windows bootstrap through Scoop and chezmoi when Nix is unavailable

## Quick start

Clone the repository and enter its dev shell:

```bash
git clone https://github.com/borland502/nix-config.git ~/.config/nix
cd ~/.config/nix
direnv allow
```

To install missing baseline tools and go-task explicitly before entering the dev shell, run:

```bash
bash ./install.sh --tools-only
```

This installs missing git and curl with apt when available, and installs go-task to `~/.local/bin` if needed. It does not run the full bootstrap.

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

Install Nix, then run activation commands in **Apple Terminal.app**:

```bash
nix develop
task switch             # auto-detects darwin
```

Use Terminal.app for `task upgrade`, `task home-switch`, rollback, and other
commands that activate configuration or modify applications too. This keeps
sudo interactive and uses Terminal's existing macOS app-management permissions.
Terminal must have the required Privacy & Security permission; an embedded
agent terminal or an allocated PTY does not provide the same application context.

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

`task switch` takes a safety snapshot when supported, records this repository as
the chezmoi source, formats and generates agent instructions, then applies chezmoi
before building and activating the detected host. `task home-switch` also applies
chezmoi before activation, without formatting or generating instructions.

## Repository layout

| Path | Purpose |
| --- | --- |
| `flake.nix` | Inputs and host outputs |
| `hosts/` | NixOS, WSL, and nix-darwin host definitions |
| `modules/` | Shared system modules |
| `home-manager/` | Shared profiles, modules, packages, and editor settings |
| `chezmoi/` | Dotfile source tree and encrypted project overlays |
| `secrets/` | SOPS-encrypted structured secrets |
| `ai-tools/` | Shared skills, agents, hooks, and automation scripts |
| `pkgs/` | Repository-owned packages and tools |
| `taskfiles/` | Quality and deployment task groups |
| `tests/` | Fixture-based helper tests |
| `docs/` | Helper-library, authentication, and agent-configuration guides |

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
| `agent-context` | Discover repository/worktree context, instructions, and direnv approval |
| `cache-scan` | Summarize retained agent sessions and artifacts |
| `gh-pr-threads` | List unresolved or filtered PR review threads |
| `gh-graphql` | Run file-backed GraphQL and jq pipelines |
| `gh-run-logs` | Persist Actions logs, with an API fallback when the normal log fetch fails |
| `gh-wait-job` | Wait for one named Actions job or a whole run |
| `monitor-gh-run` | Poll Actions without ad-hoc sleep loops |
| `aws-stack-triage` | Read-only stack summary, nesting, and failed events |
| `git-worktree-audit` | Read-only merged, unmerged, detached, stale, and dirty inventory |
| `kac` | Source and refresh temporary AWS credentials |
| `jira-get` / `confluence-get` | Authenticated reads with response validation |
| `confluence-page` | Guarded Confluence page and attachment operations |

Project-only helpers and skills are deployed from encrypted chezmoi sources.
They can compose these public primitives without exposing project topology in
this repository.

Python helpers share `agent_tools` modules, and shell hooks share source-only
libraries under `~/.local/lib`. See [Shared helper libraries](docs/helper-libraries.md)
for loading rules and offline fixture checks.

Linux desktop sessions receive a default `SUDO_ASKPASS` dispatcher. Agents can
use `sudo -A` to request a graphical password dialog when a display and helper
are available; an existing `SUDO_ASKPASS` is preserved. See
[Graphical sudo authentication](docs/sudo-askpass.md) for setup and limitations.

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

Claude's SessionEnd cache statistics require a readable transcript and skip
missing paths. Older statistics may contain aggregate totals mislabeled as
individual sessions; see [Agent token-cost levers](docs/agent-token-cost-levers.md).

## AI tooling

`chezmoi/dot_config/instructions/agent-defaults.md` is the concise source for
always-on behavior. `agent-reference.md` holds details loaded only on demand.
Generated Claude and Copilot instruction files must not be edited by hand.

```bash
task generate:agent-instructions
task check:agent-instructions
task check:copilot-instructions
task check:instruction-size
task check:agent-context-budget
task check:model-agnostic
```

Shared skills live under `ai-tools/skills/`. Claude loads them through the local
`nix-config-tools` plugin; Copilot receives linked skills and agent definitions.
On macOS, Codex receives individual skill links rather than a linked parent
directory so its discovery boundary remains explicit. Keep project-specific
skills in the project's discovery directory instead of the global set.

Agent CLIs that move faster than nixpkgs are installed by chezmoi's onchange
installer and refreshed by `task agents:update`. They are intentionally not
pinned in the flake.

### Model tiers and permissions

The configured session default is the high tier. Claude uses the `opus` alias
without versioned alias overrides. Copilot's default and a fresh Codex config
use the `sol` family; `terra` and `luna` provide the mid and low tiers.
Specialist agents still select a tier by role.

[model-tiers.nix](home-manager/lib/model-tiers.nix) defines the OpenAI model
families and minimum versions. At Home Manager activation,
[resolve-model-tiers.py](scripts/resolve-model-tiers.py) selects the newest
listed version in each family from the locally cached Codex model catalog.
If no catalog is readable, it uses the configured floors. This does not fetch
a fresh catalog or independently check Copilot availability: CLI/catalog
updates and activation are still needed to adopt newer versions.

On macOS, activation updates versioned Codex choices within their existing
family, preserves explicit aliases, and provides managed `mid.config.toml` and
`low.config.toml` profiles. Existing unmanaged profile files are left alone:

```bash
codex --profile mid
codex --profile low
```

Codex also receives scoped allow rules for selected read-only helpers. Its
macOS configuration seeds **Approve for me** with the workspace-write sandbox
only when no permission choice already exists. Explicit user permission
settings survive later activations.

### Claude hooks and workflow skills

- `bash-habits-hint` supplies advisory shell-tool guidance before Bash calls;
  `BASH_HABITS_HINT=off` disables it.
- `format-on-edit` formats edited `.nix` files in nix-config and its worktrees
  with Alejandra. It lints edited `.md` files in repositories with Markdown
  lint configuration and reports failures back to Claude.
- Cache compression runs asynchronously after a turn, alongside the existing
  session and tool-use capture hooks.
- The brainstorming workflow follows the Superpowers v7.0.2 update, with local
  model-tier guidance and cache-based plan/spec destinations. Workflow skills
  also distinguish lasting regression coverage from disposable implementation
  tests.

The format and shell-guidance hooks are wired for Claude; they are not a claim
of equivalent behavior in Codex or Copilot. Upstream skill reconciliation is
deliberate: `/reconcile-audit` reports drift before a requested re-sync.

### MCP tools and skill evaluations

[Serena](https://github.com/oraios/serena) supplies symbol lookup, references,
and targeted code edits through a local MCP server. Home Manager installs
`serena` and `serena-mcp`, configures Copilot CLI, and seeds missing user-level
entries for Claude Code and macOS Codex. Existing Claude/Codex server entries
are preserved. Start a new agent session after activation to load the tools.

The launcher uses Serena 2.1.0 through uv with Nix Python 3.13. Its compact
REPL interface starts over stdio with the dashboard disabled and discovers the
project from the client's working directory. Run `serena --help` for project
setup options. First use downloads Python dependencies; individual language
servers may need additional downloads or project-specific configuration.

The same clients receive three complementary MCP servers:

| Server | Purpose | Connection |
| --- | --- | --- |
| [Context7](https://github.com/upstash/context7) | Library documentation and code examples | Hosted documentation service; no key required for the basic tier |
| [AWS Knowledge](https://github.com/awslabs/mcp/tree/main/src/aws-knowledge-mcp-server) | AWS documentation and service information | Public AWS-hosted documentation service; no AWS credentials required |
| [Playwright MCP](https://github.com/microsoft/playwright-mcp) | Browser navigation, interaction, and page inspection | Local stdio server using a headless, isolated browser session |

Documentation queries go to the respective hosted service. Playwright MCP
0.0.86 runs through the managed `playwright-mcp` launcher, uses the installed
Google Chrome on macOS and Nix Chromium on Linux, and puts generated output
under `~/.cache/codex/playwright-mcp`. Its isolated sessions do not reuse your
normal browser profile. The existing Playwright CLI skill remains available
for repeatable shell-based browser workflows.

[Skillgrade](https://github.com/mgechev/skillgrade) runs repeatable tasks to
check how well agent skills work. The managed `skillgrade` launcher uses
version 0.5.0 with a private Nix Node runtime; it leaves the shell's nvm choice
intact. npm downloads its dependencies on first use. The included
[shell-pitfalls evaluation](evals/shell-pitfalls) checks command behavior with
awkward filenames and verifies that unrelated files survive:

```bash
task eval:skills:list       # inspect tasks; no model calls
task eval:skills:validate   # check the reference solution; no model calls
task eval:skills            # run one model-backed trial
```

Model-backed evaluation is explicit and uses the selected agent's credentials;
ordinary lint and build tasks do not run it. Results and temporary workspaces
stay under `~/.cache/codex/skillgrade`. See the evaluation's README for options
and the difference between validating a grader and measuring an agent.

## Editor and report tools

VS Code profiles and their extensions are managed by Nix. The Nix and Shell
profiles include Task support; YAML and Markdown linting are shared across
profiles, and the Go, Python, Java and NodeJS profiles include REST Client.
Formatters are selected per profile, and Ruff discovers project configuration
normally. Settings Sync excludes the Nix-managed settings and extension IDs;
other synced data remains subject to VS Code's sync configuration. Apply changes
through the normal Home Manager workflow rather than editing managed settings.

The managed VS Code Java extension keeps language-server and runtime paths at
machine scope so project settings cannot redirect them to a missing JDK. The
project's build still controls its target Java version.

The repository's [htmlpdf package](pkgs/htmlpdf) renders report PDFs and checks
their layout. Its default report profile uses readable footer text. Agent
document skills provide the corresponding authoring and verification workflow.

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
task check:agent-tools   # offline Python and shell regression fixtures
```

Install the tracked pre-commit hooks once per clone:

```bash
task hooks:install
```

The hooks enforce formatting, generated-instruction consistency, instruction
size, model-agnostic skill metadata, and public-repository secret hygiene.

## Shell scripts

New scripts are zsh. The floor is zsh 5.9, the version macOS ships as `/bin/zsh`, so a
script runs the same on a stock Mac, NixOS, WSL and any Home Manager host.

```zsh
#!/usr/bin/env -S zsh -f
# <one-line purpose>
emulate -R zsh
setopt err_exit no_unset pipe_fail
```

- bash is limited to `install.sh` and the legacy scripts in `scripts/bash-allowlist.txt`.
  `install.sh` is the bootstrap: it runs before zsh is guaranteed, so it must work
  under bash 3.2 (`tests/test_install_bootstrap.py`). Scripts built by Nix
  (`writeShellApplication`) keep nixpkgs bash.
- The `-f` in the shebang keeps your `~/.zshenv` from rewriting the PATH the script was given.
- `task lint:sh` checks zsh with `zsh -n` and `shfmt` (zsh dialect). ShellCheck has no zsh
  support. shfmt cannot parse a few zsh short forms (`for k v in`, `for x (…)`,
  `repeat N { }`, `${~x}`/`${=x}`/`${^x}`), so use the long forms.
- Inside a function, `$0` is the function's name: capture `script=${0:A}` at the top.
  Split lines with the quoted form `${(f)"$(cmd)"}`.

## Maintenance

```bash
task update && task switch
task upgrade
task gc
task optimize
```

Before changing a host or module, prefer the smallest build that exercises it.
Use `task build` to build without activating, and activate only after the build
passes. Repository-owned packages expose their own namespaced `task` checks.

## License and credits

The configuration is personal and public; reuse it selectively rather than as
a drop-in host configuration. Third-party skill origins and licenses are
recorded in each skill's frontmatter and upstream notices.

Substantial sources and influences include:

| Repository | Contribution to this configuration |
| --- | --- |
| [obra/superpowers](https://github.com/obra/superpowers) | Adapted planning, brainstorming, debugging, testing, review, and subagent workflows; the current brainstorming refresh follows v7.0.2. |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | Source for ECC-marked operational skills and inspiration for formatter/linter feedback after edits; the local hooks are implemented for this repository's tools and boundaries. |
| [anthropics/skills](https://github.com/anthropics/skills) | A separately registered upstream Claude marketplace; document skills are loaded from upstream rather than copied into this repository. |
| [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) | Origin of the adapted Defuddle skill for extracting readable web content. |
| [oraios/serena](https://github.com/oraios/serena) | Local MCP code navigation and editing, connected to the managed coding-agent clients. |
| [mgechev/skillgrade](https://github.com/mgechev/skillgrade) | Behavioral evaluation runner for the repository's skill fixtures and reference-solution checks. |
| [upstash/context7](https://github.com/upstash/context7) | Hosted library-documentation MCP integration. |
| [awslabs/mcp](https://github.com/awslabs/mcp) | AWS Knowledge documentation MCP and the existing AWS API MCP tooling. |
| [microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp) | Browser automation MCP with isolated browser sessions. |

The [chezmoi externals](chezmoi/.chezmoiexternal.toml.tmpl) also retain upstream
checkouts for reconciliation and project-specific guidance. These credits
describe actual use or adaptation; each upstream retains its own license and
terms.
