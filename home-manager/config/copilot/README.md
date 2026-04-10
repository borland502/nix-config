# Copilot Defaults

This directory contains the tracked source file used by Home Manager to install
Copilot defaults across editors:

- `copilot-defaults.instructions.md`

If you are not using Home Manager, you can manually copy or symlink that file
into the same user-level locations to get the equivalent behavior.

## Source File

Use this file as the source of truth:

```text
home-manager/config/copilot/copilot-defaults.instructions.md
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
