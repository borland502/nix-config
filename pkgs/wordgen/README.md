# wordgen

`wordgen` generates filtered random words from a JSON index built from
the word lists stored under `assets/`.

The CLI uses:

- [`spf13/cobra`](https://github.com/spf13/cobra) for commands and flags
- [`spf13/viper`](https://github.com/spf13/viper) for config files,
  environment variables, and flag binding
- [`adrg/xdg`](https://github.com/adrg/xdg) for XDG-aware config discovery
  and creation

The main `generate` command streams a JSON index from
`embedded://all.json.zst` (default), `assets/all.json`,
`assets/all.json.gz`, or `assets/all.json.zst`, filters words by
length, prefix, substring, or source file, and returns a random sample
without loading the full index into memory.

## Library Usage

`wordgen` can also be used as a Go library via `pkg/wordgen`.

```go
package main

import (
	"context"
	"fmt"

	"github.com/borland502/wordgen/pkg/wordgen"
)

func main() {
	words, matched, err := wordgen.Generate(context.Background(), wordgen.Config{
		Dataset:   "embedded://all.json.zst",
		Count:     5,
		MinLength: 4,
		MaxLength: 8,
		Prefix:    "st",
	})
	if err != nil {
		panic(err)
	}

	fmt.Printf("matched=%d words=%v\n", matched, words)
}
```

For repeated low-latency calls, load an indexed in-memory backend once:

```go
indexed, err := wordgen.LoadIndexed("embedded://all.json.zst")
if err != nil {
	panic(err)
}

words, matched, err := indexed.Generate(context.Background(), wordgen.Config{
	Count:     5,
	MinLength: 4,
	MaxLength: 8,
})
_ = matched
_ = words
_ = err
```

## Requirements

- Go `1.25.8`
- `direnv`
- `task`

If `direnv` is enabled for the repo, `.envrc` will verify the Go
version from `go.mod` and install local copies of Go and Task under
`.tools/` when needed.

## Quick Start

```bash
direnv allow .
task build-words-json
task generate -- --config ./configs/wordgen.toml
```

Run the generator directly:

```bash
go run . --config ./configs/wordgen.toml
go run . generate --config ./configs/wordgen.toml
go run . generate --count 8 --min-length 6 --source fsu/wordle.txt
```

Create a starter config in the default XDG location:

```bash
go run . init-config
```

## Configuration

The default user config path is:

- Linux: `$XDG_CONFIG_HOME/wordgen/config.toml` or `~/.config/wordgen/config.toml`
- macOS: `~/Library/Application Support/wordgen/config.toml`
- Windows: `%LOCALAPPDATA%\wordgen/config.toml`

You can also point the CLI at an explicit config file:

```bash
go run . --config ./configs/wordgen.toml
go run . generate --config ./configs/wordgen.toml
```

Config structure:

```toml
[generate]
dataset = "embedded://all.json.zst"
count = 5
min_length = 4
max_length = 10
prefix = ""
contains = ""
sources = []
seed = 0
```

The `dataset` value can be `embedded://all.json.zst` (default), or it
can point at a generated JSON index path. `assets/all.json.zst` and
`assets/all.json.gz` are supported, and `assets/all.json` can be used
when maximum decode speed is preferred. The repository config in
`configs/wordgen.toml` also includes the `[[sources]]` entries used to
rebuild all outputs.

Environment variables override config values. Examples:

```bash
WORDGEN_GENERATE_COUNT=3 go run .
WORDGEN_GENERATE_COUNT=3 go run . generate --config ./configs/wordgen.toml
WORDGEN_GENERATE_PREFIX="pre" go run . generate --config ./configs/wordgen.toml
WORDGEN_GENERATE_DATASET="embedded://all.json.zst" go run . generate
```

## Commands

- `wordgen` (no subcommand): runs default generation using config and environment values
- `wordgen generate`: emit random words from the indexed datasets
- `wordgen init-config`: write a starter config file

## Development

Common workflows are in `Taskfile.yml`:

```bash
task fmt
task check
task build
task generate -- --config ./configs/wordgen.toml --count 10 --source fsu/wordle.txt
task build-words-json
```

`task build` writes the full local binary to `./tmp/build/wordgen` so
it is not disturbed by `go test ./...`.

Local install and removal tasks are also available:

```bash
task deploy
task undeploy
```

These tasks are intended for POSIX shells on Linux and macOS.

Both tasks accept overrides for the install and config locations when
you need a safe or custom target:

```bash
task deploy INSTALL_DIR=./tmp/bin CONFIG_PATH=./tmp/wordgen/config.toml
task undeploy INSTALL_DIR=./tmp/bin CONFIG_PATH=./tmp/wordgen/config.toml
```

`task deploy` installs a stripped binary, while `task undeploy`
removes the installed binary, any task-generated config file, and local
build artifacts for the project.

## Sources

The word list source files stored in `assets/` were downloaded from:

- <https://people.sc.fsu.edu/~jburkardt/datasets/words/words.html>
- <https://apiacoa.org/publications/teaching/datasets/google-10000-english.txt>
- <https://github.com/dwyl/english-words/tree/master>

The downloaded source files currently live under owner or domain
subdirectories in `assets/`, including `assets/fsu/`,
`assets/apiacoa/`, and `assets/dwyl/`.

The configured source-of-truth for which dataset files are included in
`assets/all.json`, `assets/all.json.gz`, and `assets/all.json.zst` is
`configs/wordgen.toml` under the `[[sources]]` entries.

The generated `assets/all.json`, `assets/all.json.gz`, and
`assets/all.json.zst` files are built from those downloaded `.txt`
dictionaries by running:

```bash
task build-words-json
```

By default this builds only `assets/all.json.zst`. To explicitly
include additional artifacts during a build:

```bash
task build-words-json -- --include-json --include-gzip
```

## Workflow Credit

The GitHub Actions workflows in
[`.github/workflows`](https://github.com/borland502/wordgen/tree/main/.github/workflows)
are adapted from the workflow layout used by
[`charmbracelet/gum`](https://github.com/charmbracelet/gum/tree/main/.github/workflows),
simplified for this repository.

## License

This project is licensed under the MIT License. See `LICENSE`.
