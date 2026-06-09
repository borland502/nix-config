---
name: "zsh-pitfalls-and-defaults"
description: "Reusable zsh safety defaults for agent terminal work."
applyTo: "**"
---

# Zsh Pitfalls And Defaults

Use these defaults whenever you generate or run zsh commands.

## Variable Safety

- Never use `path` as a normal variable name in zsh. It is a special array tied to `PATH`.
- Avoid assigning to `PATH` unless intentionally updating command lookup.
- Never use `status` as a variable name in zsh. It is read-only. Use `rc` or `exit_code`.

## Quoting And Expansion

- Quote variables by default: `"$var"`.
- Quote file paths that may include spaces.
- Use `$(...)` command substitution, not backticks.
- Do not emit bare `==` or `===` as standalone shell text. Quote those strings.

## Command Construction

- Prefer short, stable inline commands.
- For long JSON, scripts, or heavily quoted payloads, write a temporary script file under `~/.cache/copilot` (or `~/.cache/claude`) and execute that file.
- Prefer `rg` over `grep` and `fd` over `find` when available.

## Execution Defaults

- If shell output looks mangled due to prompt fragments or quote breakage, rerun from an isolated shell.
- Log command input and output to a cache log file for reproducibility.
- Use `/bin/cat` when raw file output is required and shell aliases may map `cat` to `bat`.

## AWS Credential Safety (Environment-Specific)

- Prefer loading temporary AWS credentials from `~/.cache/kion-aws-cache/` when the local environment uses Kion.
- Treat values from credentials files as secrets and never echo them in summaries.

## Quick Checklist

- No `path` variable misuse.
- No `status` variable misuse.
- Quotes added around variable expansions and paths.
- Long/quoted payload moved to a script file.
- Command and output logged under cache.
