# Shared helper libraries

Managed helpers share Python code in [agent_tools](../chezmoi/dot_local/lib/agent_tools) and source-only Bash code in [shell](../chezmoi/dot_local/lib/shell). Chezmoi installs these under `~/.local/lib`. Keep command arguments, presentation, and service-specific policy in the entry points.

| Module | Responsibility |
| --- | --- |
| `agent_tools.sources` | Git-aware Python and shell source discovery for the lint commands |
| `agent_tools.atlassian_cli` | Common Jira/Confluence GET command behavior |
| `agent_tools.process` | Checked subprocess execution, timeout errors, and JSON decoding |
| `agent_tools.artifacts` | Private directories and atomic file publication |
| `shell/agent-cache.bash` | Agent-name normalization and existing home-cache path construction |
| `shell/hook-log.bash` | Truncation, hook record formatting, and private append |

## Loading libraries

Python consumers retain small entry-point bootstraps for source-tree and installed execution. `AGENT_TOOLS_LIB` selects an explicit library directory where supported; a global `PYTHONPATH` is unnecessary. Repository lint commands always import the checkout's library.

Managed shell hooks receive `AGENT_TOOLS_SHELL_LIB` from Home Manager wrappers. Source-tree fixtures pass the same override. The standalone zsh `gh-run-logs` command loads its sibling `lib/shell` directory (resolved from `${0:A}`), so `agent-cache.bash` must stay valid under both bash and `emulate -R zsh` with `no_unset`.

[agent-tools-libraries.nix](../home-manager/lib/agent-tools-libraries.nix) defines the shared Python and shell store sources. The Python source excludes bytecode and non-Python files. Wrappers use store paths rather than assuming a script symlink has a neighboring library.

## Behavior contracts

- Sourcing a shell module defines functions without changing options, traps, cwd, or umask. `agent_hook_append` scopes its private umask to a subshell.
- `agent_cache_path` takes a home directory and normalized agent name. Callers retain their existing cache-root overrides and fallback policies; the helper does not select a new XDG policy.
- Hook callers own event parsing, stderr classification, redaction, cursor state, and truncation messages. The shared formatter retains the scanner's session record schema.
- `get_main` preserves raw successful response bytes; HTTP configuration and pagination stay in the existing Atlassian client.
- `ProcessTimeout` is a `ProcessError` subtype. `run_json` decodes only successful command output. Callers choose timeout budgets and distinguish prose-producing commands from JSON reads.
- `atomic_output` publishes only after its context exits successfully. Validate stream content inside the context; use `before_publish` for a final check after the temporary file has been synced and closed. `private_directory` rejects a symlink at the target directory; ancestry containment and target-file policy remain caller responsibilities.
- Kion's locking and multi-file publication protocol remains separate from single-file artifact helpers.

## Validation

Declare source-only Bash libraries with `# shellcheck shell=bash` so shell discovery includes them, and list them in [bash-allowlist.txt](../scripts/bash-allowlist.txt) until their bash callers convert to zsh. Keep fixtures offline, using temporary homes and fake commands; do not run installed automation hooks by hand.

Run the repository's allowed direnv environment, then:

```sh
task check:agent-tools
task lint:py
task lint:sh
task check:secret-hygiene
```

Tests cover source-tree, installed sibling-directory, and relocated-script library loading. Configuration builds verify packaging separately from host activation.
