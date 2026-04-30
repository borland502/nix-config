# Copilot Defaults

The Copilot defaults are now federated from a shared markdown source that also
produces the Claude `CLAUDE.md`. The source lives at:

```text
home-manager/config/instructions/agent-defaults.md
```

It uses the literal placeholder `@@AGENT@@` wherever the agent name should
appear (e.g. in `~/.cache/@@AGENT@@`). Home Manager renders two derivations
from it via `home-manager/lib/agent-instructions.nix`:

- `copilot-defaults.instructions.md` — placeholder replaced with `copilot`,
  Copilot YAML frontmatter prepended.
- `CLAUDE.md` — placeholder replaced with `claude`, no frontmatter.

If you are not using Home Manager, you can produce a directly-usable Copilot
file by substituting the placeholder yourself:

```sh
sed 's/@@AGENT@@/copilot/g' \
  home-manager/config/instructions/agent-defaults.md \
  > /tmp/copilot-defaults.instructions.md
# then prepend the Copilot frontmatter (see lib/agent-instructions.nix) and
# copy or symlink the result into the locations below.
```

## Source File

Use this file as the source of truth:

```text
home-manager/config/instructions/agent-defaults.md
```

## VS Code Targets

### VS Code macOS

Copy or symlink the source file to:

```text
~/Library/Application Support/Code/User/prompts/copilot-defaults.instructions.md
```

Example:

```sh
mkdir -p "$HOME/Library/Application Support/Code/User/prompts"
ln -sf "$HOME/.config/nix/home-manager/config/copilot/copilot-defaults.instructions.md" \
  "$HOME/Library/Application Support/Code/User/prompts/copilot-defaults.instructions.md"
```

### VS Code Linux

Copy or symlink the source file to:

```text
~/.config/Code/User/prompts/copilot-defaults.instructions.md
```

Example:

```sh
mkdir -p "$HOME/.config/Code/User/prompts"
ln -sf "$HOME/.config/nix/home-manager/config/copilot/copilot-defaults.instructions.md" \
  "$HOME/.config/Code/User/prompts/copilot-defaults.instructions.md"
```

## VS Code Insiders Targets

### VS Code Insiders macOS

Copy or symlink the source file to:

```text
~/Library/Application Support/Code - Insiders/User/prompts/copilot-defaults.instructions.md
```

Example:

```sh
mkdir -p "$HOME/Library/Application Support/Code - Insiders/User/prompts"
ln -sf "$HOME/.config/nix/home-manager/config/copilot/copilot-defaults.instructions.md" \
  "$HOME/Library/Application Support/Code - Insiders/User/prompts/copilot-defaults.instructions.md"
```

### VS Code Insiders Linux

Copy or symlink the source file to:

```text
~/.config/Code - Insiders/User/prompts/copilot-defaults.instructions.md
```

Example:

```sh
mkdir -p "$HOME/.config/Code - Insiders/User/prompts"
ln -sf "$HOME/.config/nix/home-manager/config/copilot/copilot-defaults.instructions.md" \
  "$HOME/.config/Code - Insiders/User/prompts/copilot-defaults.instructions.md"
```

### VS Code Remote / WSL

If you want the same defaults in remote sessions, also copy or symlink the file
to:

```text
~/.vscode-server/data/User/prompts/copilot-defaults.instructions.md
```

Example:

```sh
mkdir -p "$HOME/.vscode-server/data/User/prompts"
ln -sf "$HOME/.config/nix/home-manager/config/copilot/copilot-defaults.instructions.md" \
  "$HOME/.vscode-server/data/User/prompts/copilot-defaults.instructions.md"
```

### VS Code Insiders Remote / WSL

If you want the same defaults in remote Insiders sessions, also copy or symlink
the file to:

```text
~/.vscode-server-insiders/data/User/prompts/copilot-defaults.instructions.md
```

Example:

```sh
mkdir -p "$HOME/.vscode-server-insiders/data/User/prompts"
ln -sf "$HOME/.config/nix/home-manager/config/copilot/copilot-defaults.instructions.md" \
  "$HOME/.vscode-server-insiders/data/User/prompts/copilot-defaults.instructions.md"
```

## GitHub Copilot User Config Targets

Home Manager also places the same file under `~/.config/github-copilot`.
If you want to mirror that manually, use these paths.

### Shared Alias

```text
~/.config/github-copilot/copilot-defaults.instructions.md
```

Example:

```sh
mkdir -p "$HOME/.config/github-copilot"
ln -sf "$HOME/.config/nix/home-manager/config/copilot/copilot-defaults.instructions.md" \
  "$HOME/.config/github-copilot/copilot-defaults.instructions.md"
```

### JetBrains / IntelliJ Global Copilot Instructions

```text
~/.config/github-copilot/intellij/global-copilot-instructions.md
```

Example:

```sh
mkdir -p "$HOME/.config/github-copilot/intellij"
ln -sf "$HOME/.config/nix/home-manager/config/copilot/copilot-defaults.instructions.md" \
  "$HOME/.config/github-copilot/intellij/global-copilot-instructions.md"
```

## Repository-Level Copilot Instructions

This repository also has a repository-level Copilot file at:

```text
.github/copilot-instructions.md
```

That file is for repository-scoped Copilot behavior. It is separate from the
user-level defaults above.

## Notes

- Symlinks are the closest manual equivalent to the Home Manager `.source`
  mapping used in `home-manager/common.nix`.
- If you prefer copies instead of symlinks, replace `ln -sf` with `cp`.
- After updating the source file, restart the editor if the extension does not
  immediately pick up the change.
