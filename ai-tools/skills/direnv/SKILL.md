---
name: direnv
description: direnv — automatic per-directory environment variable loading via .envrc files. Use when debugging why env vars aren't loading, writing .envrc files, or managing direnv authorization.
---

# direnv

`direnv` hooks into the shell and automatically loads/unloads environment variables defined in `.envrc` (or `.env`) files when you `cd` into or out of a directory. It is mostly automatic once set up; this skill covers the non-obvious parts.

## How It Works

1. Shell hook fires on every `cd`.
2. direnv looks for `.envrc` or `.env` in the current directory and parents.
3. If found and authorized, it `source`s the file in a restricted subshell and exports the resulting env diff into the current shell.
4. On `cd` away, it unexports those variables.

## Authorization

direnv requires explicit authorization before loading any `.envrc`. This is a security measure — any new or modified file must be re-authorized.

```bash
# Authorize the .envrc in the current directory
direnv allow

# Authorize a specific file
direnv allow /path/to/project/.envrc

# Revoke authorization
direnv deny

# Edit .envrc and automatically re-authorize on save
direnv edit
```

## Debugging

```bash
# Show what direnv currently sees (loaded vars, allowed status, watch list)
direnv status

# Show the full stdlib available inside .envrc
direnv stdlib

# Manually trigger a reload without changing directories
direnv reload

# Dry-run: print the env diff that would be exported
direnv export zsh
```

## Writing .envrc Files

```bash
# Basic variable export
export DATABASE_URL="postgres://localhost/mydb"
export PORT=3000

# Load a .env file (common pattern)
dotenv

# Use direnv stdlib helpers
layout python3         # Sets up a virtualenv in .direnv/
layout node            # Adds node_modules/.bin to PATH
use flake              # Activate a Nix flake devShell

# Source another file relative to the project root
source_env .env.local

# Extend PATH
PATH_add bin
PATH_add scripts
```

## Common Patterns

```bash
# Project-specific AWS profile
export AWS_PROFILE=my-project-dev

# Per-project Go environment
export GOPATH="$PWD/.gopath"
PATH_add .gopath/bin

# Nix flake devShell (preferred for Nix projects)
use flake
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `direnv: error .envrc is blocked` | File not authorized | `direnv allow` |
| Vars not loading after editing `.envrc` | File needs re-authorization | `direnv allow` |
| `direnv: error loading .envrc` | Syntax error in file | `direnv edit` and check the error |
| Vars not unloading on `cd` away | Shell hook not installed | Check `~/.zshrc` for `eval "$(direnv hook zsh)"` |
| Slow shell prompt | Large `.envrc` or heavy stdlib call | Profile with `time direnv export zsh` |

## Best Practices

- Never commit secrets directly in `.envrc`. Use `dotenv .env.secret` and `.gitignore` the secret file.
- Use `direnv edit` instead of editing `.envrc` directly — it re-authorizes automatically on save.
- For Nix projects, `use flake` replaces manual `nix develop` calls and keeps the dev shell in sync.
- Add `.direnv/` to `.gitignore` — it holds virtualenvs and cached layouts.
