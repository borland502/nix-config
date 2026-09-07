# gopwgen

`gopwgen` is a secure passphrase generator built on the `wordgen` library and demonstrates how to combine these Go libraries in one project:

- [`github.com/borland502/wordgen`](https://github.com/borland502/wordgen) for efficient word generation with embedded datasets
- [`spf13/cobra`](https://github.com/spf13/cobra) for commands and flags
- [`spf13/viper`](https://github.com/spf13/viper) for config files, environment variables, and flag binding
- [`adrg/xdg`](https://github.com/adrg/xdg) for XDG-aware config discovery and creation

The main `password` command generates secure passphrases from random words with optional special characters to meet common password requirements. Passphrases can be customized with word count, separator, case formatting (Traincase, camelCase, etc.), and automatic appending of digits and special characters.

Example output: `Harbor-Lantern-Maple-Canvas-Breeze7!`

## Requirements

- Go `1.25.8`
- `direnv`
- `task`

If `direnv` is enabled for the repo, `.envrc` will verify the Go version from `go.mod` and install local copies of Go and Task under `.tools/` when needed.

## Quick Start

```bash
direnv allow .
task build
```

Generate a secure passphrase:

```bash
go run . password
```

Generate multiple passphrases with custom settings:

```bash
go run . password --batch 3 --word-count 6 --separator "_"
go run . password --case-format camelcase
```

Create a starter config in the default XDG location:

```bash
go run . init-config
```

## Configuration

The default user config path is:

- Linux: `$XDG_CONFIG_HOME/gopwgen/config.toml` or `~/.config/gopwgen/config.toml`
- macOS: `~/Library/Application Support/gopwgen/config.toml`
- Windows: `%LOCALAPPDATA%\gopwgen\config.toml`

You can also point the CLI at an explicit config file:

```bash
go run . password --config ./configs/gopwgen.toml
```

Password configuration supports the following options:

```toml
[password]
# Number of words in passphrase (default: 5)
word_count = 5
# Maximum characters per word, filtered via wordgen (max 12)
max_word_length = 12
# Separator between words (default: -)
separator = "-"
# Case formatting: traincase, camelcase, lower, upper, title, none
case_format = "traincase"
# Append digits and special characters for common password requirements
append_requirements = true
# Individual requirement flags (only used if append_requirements is true)
require_uppercase = true
require_lowercase = true
require_numbers = true
require_special = true
# Built-in wordgen dataset (embedded://all.json.zst for offline use)
wordgen_dataset = "embedded://all.json.zst"
```

### Password Format Examples

With default config (5 words, dash separator, traincase, with requirements):

```text
Word-Word-Word-Word-Word6!
Shrimpi-Nontruth-Kamba-Stream-Institute2$
```

With camelcase and underscore separator:

```text
camelCase-Lowercase-Word-Word-Word8^
```

With custom word count (3 words):

```text
Disorganise-Baldridge-Thermels0&
```

Environment variables override config values. Examples:

```bash
GOPWGEN_PASSWORD_WORD_COUNT=6 go run . password
GOPWGEN_PASSWORD_SEPARATOR="_" go run . password
GOPWGEN_PASSWORD_CASE_FORMAT="camelcase" go run . password
```

## Commands

- `gopwgen password`: generate secure passphrases from random words
- `gopwgen init-config`: write a starter config file
- `gopwgen version`: show build version metadata

## Development

Common workflows are in `Taskfile.yml`:

```bash
task fmt
task check
task build
task password -- --word-count 6 --separator "_"
```

`task build` writes the full local binary to `./tmp/build/gopwgen` so it
is not disturbed by `go test ./...`.

Local install and removal tasks are also available:

```bash
task deploy
task undeploy
```

These tasks are intended for POSIX shells on Linux and macOS.

Both tasks accept overrides for the install and config locations when you need a safe or custom target:

```bash
task deploy INSTALL_DIR=./tmp/bin CONFIG_PATH=./tmp/gopwgen/config.toml
task undeploy INSTALL_DIR=./tmp/bin CONFIG_PATH=./tmp/gopwgen/config.toml
```

`task deploy` installs a stripped binary, while `task undeploy`
removes the installed binary, any task-generated config file, and local
build artifacts for the project.

## Releases

Releases are tagged automatically from pushes to `main`.

The auto-tag workflow inspects commit messages on `main` and creates the next semver tag, which then triggers GoReleaser:

- `fix:` or `perf:` => patch release
- `feat:` => minor release
- `feat!:` or any `BREAKING CHANGE:` footer => major release
- `docs:`, `test:`, `chore:`, `ci:` and other non-release changes => no tag

If you use squash merges, the PR title becomes the release signal, so keep merged PR titles in conventional commit format.

## Workflow Credit

The GitHub Actions workflows in [`.github/workflows`](https://github.com/borland502/go-sea/tree/main/.github/workflows) are adapted from the workflow layout used by [`charmbracelet/gum`](https://github.com/charmbracelet/gum/tree/main/.github/workflows), simplified for this repository.

## License

This project is licensed under the MIT License. See `LICENSE`.
