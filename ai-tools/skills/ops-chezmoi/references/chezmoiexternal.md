# `.chezmoiexternal.<format>`

> Mirrored from <https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/> for offline reference.

If a file called `.chezmoiexternal.$FORMAT` (with an optional `.tmpl` extension) exists anywhere in the source state (either `~/.local/share/chezmoi` or directory defined inside `.chezmoiroot`), it is interpreted as a list of external files and archives to be included as if they were in the source state. See also `.chezmoiexternals/` directories.

`$FORMAT` must be one of chezmoi's supported configuration file formats: JSON, JSONC, TOML, or YAML.

`.chezmoiexternal.$FORMAT` is interpreted as a template, whether or not it has a `.tmpl` extension. This allows different externals to be included on different machines.

If a `.chezmoiexternal.$FORMAT` file is located in an ignored directory (one listed in `.chezmoiignore`), all entries within the file are also ignored.

Entries are indexed by target name relative to the directory of the `.chezmoiexternal.$FORMAT` file, and must have a `type` and a `url` and/or a `urls` field. `type` can be either `file`, `archive`, `archive-file`, or `git-repo`. If the entry's parent directories do not already exist in the source state then chezmoi will create them as regular directories.

## Entry Fields

| Variable | Type | Default | Description |
|---|---|---|---|
| `type` | string | _none_ | External type (`file`, `archive`, `archive-file`, or `git-repo`) |
| `decompress` | string | _none_ | Decompression for file |
| `encrypted` | bool | `false` | Whether the external is encrypted |
| `exact` | bool | `false` | Add `exact_` attribute to directories in archive |
| `exclude` | []string | _none_ | Patterns to exclude from archive |
| `executable` | bool | `false` | Add `executable_` attribute to file |
| `private` | bool | `false` | Add `private_` attribute to file |
| `readonly` | bool | `false` | Add `readonly_` attribute to file |
| `format` | string | _autodetect_ | Format of archive |
| `path` | string | _none_ | Path to file in archive |
| `include` | []string | _none_ | Patterns to include from archive |
| `refreshPeriod` | duration | `0` | Refresh period |
| `stripComponents` | int | `0` | Number of leading directory components to strip |
| `url` | string | _none_ | URL |
| `urls` | []string | _none_ | Extra URLs to try, in order |
| `checksum.sha256` | string | _none_ | Expected SHA256 checksum of data |
| `checksum.sha384` | string | _none_ | Expected SHA384 checksum of data |
| `checksum.sha512` | string | _none_ | Expected SHA512 checksum of data |
| `checksum.size` | int | _none_ | Expected size of data |
| `clone.args` | []string | _none_ | Extra args to `git clone` |
| `filter.command` | string | _none_ | Command to filter contents |
| `filter.args` | []string | _none_ | Extra args to filter command |
| `pull.args` | []string | _none_ | Extra args to `git pull` |
| `archive.extractAppleDouble` | bool | `false` | If `true`, AppleDouble files are extracted |
| `targetPath` | string | _none_ | Target path, overriding the entry key |

## URL Requirements

`url` must be `https://`, `http://`, or `file://`. If `urls` is specified, they are tried in order; the first to succeed is used. If any of `checksum.sha256`/`sha384`/`sha512` are set, the downloaded data is verified.

## Encryption and Decompression

`encrypted` declares whether the file/archive is encrypted. `decompress` controls how the file is decompressed; supported: `bzip2`, `gzip`, `xz`, `zstd`. `.rar` and `.zip` are archives — use `archive-file` to extract a single file from them.

## Filtering

If `filter.command` (and optional `filter.args`) is set, the data is piped through that command before being treated as the file/archive contents.

## Type: `file`

The target is a single file with the contents of `url`. `executable: true` makes it executable.

## Type: `archive`

The target is a directory holding the contents of the archive at `url`. `exact: true` causes chezmoi to remove anything not in the archive on subsequent applies. `stripComponents` removes that many leading path components. `format` overrides autodetection; supported: `tar`, `tar.gz`, `tgz`, `tar.bz2`, `tbz2`, `xz`, `tar.zst`, `zip`. `archive.extractAppleDouble: true` extracts AppleDouble metadata files (off by default).

### Include and Exclude Patterns

`include` / `exclude` are lists of glob patterns matching paths in the archive (not target paths). Resolution order:

1. If the member matches any `exclude`, it is excluded (recursively for directories).
2. Else if it matches any `include`, it is included.
3. Else if only `include` patterns were specified, it is excluded.
4. Else if only `exclude` patterns were specified, it is included.
5. Else it is included.

## Type: `archive-file`

The target is a single file (or symlink) extracted from the entry `path` inside the archive at `url`. `stripComponents` is applied before matching `path`. `executable: true` sets the executable bit on the target even if the archive does not.

> Be sure to check that you have the correct `path` for the file in your archive — for example, `tar tzf x.tar.gz` to inspect.

## Type: `git-repo`

If the target does not exist, chezmoi runs `git clone $URL $TARGET_NAME` (with optional `clone.args`). If it exists, chezmoi runs `git pull` (with optional `pull.args`) to update it. This is the type used by every entry in this project's [.chezmoiexternal.toml.tmpl](../../../../chezmoi/.chezmoiexternal.toml.tmpl).

## Caching and Refresh

For `file` and `archive` externals chezmoi caches downloaded URLs. `refreshPeriod` (a Go `time.Duration`) controls how often chezmoi re-downloads. Default `0` means never re-download unless forced. To force a refresh now: `chezmoi apply --refresh-externals` (alias `chezmoi update`). Suitable values include `24h`, `168h` (1 week), `672h` (4 weeks). This project uses `720h` (~1 month).

## Examples

### Basic TOML

```toml
[".vim/autoload/plug.vim"]
    type = "file"
    url = "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
    refreshPeriod = "168h"

[".oh-my-zsh"]
    type = "archive"
    url = "https://github.com/ohmyzsh/ohmyzsh/archive/master.tar.gz"
    exact = true
    stripComponents = 1
    refreshPeriod = "168h"

[".local/bin/age"]
    type = "archive-file"
    url = "https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-{{ .chezmoi.os }}-{{ .chezmoi.arch }}.tar.gz"
    path = "age/age"

["www/adminer/plugins"]
    type = "archive"
    url = "https://api.github.com/repos/vrana/adminer/tarball"
    refreshPeriod = "744h"
    stripComponents = 2
    include = ["*/plugins/**"]
```

### `targetPath` (multiple entries → one directory)

```toml
[p10k_fonts]
    type = "archive"
    url = "https://github.com/romkatv/powerlevel10k-media/archive/master.tar.gz"
    stripComponents = 1
    refreshPeriod = "168h"
    include = ["*/*.ttf"]
    targetPath = "Library/Fonts"

[source_code_pro]
    type = "archive"
    url = "https://github.com/adobe-fonts/source-code-pro/archive/master.tar.gz"
    stripComponents = 2
    refreshPeriod = "168h"
    include = ["**/*.ttf"]
    targetPath = "Library/Fonts"
```

### Private git repo (template-gated on key presence)

```toml
{{ if stat (joinPath .chezmoi.homeDir ".ssh" "id_rsa") }}
[".path/to/private/repo"]
    type = "git-repo"
    url = "git@private.com:org/repo.git"
{{ end }}
```

This project's externals are all `type = "git-repo"` over HTTPS with a `pull.args = ["--ff-only"]` override; see [chezmoi/.chezmoiexternal.toml.tmpl](../../../../chezmoi/.chezmoiexternal.toml.tmpl).
