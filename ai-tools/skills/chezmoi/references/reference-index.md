# Reference index

> Mirrored from <https://www.chezmoi.io/reference/> for offline navigation.
> Each link points at the upstream page; fetch and capture into this folder
> if it becomes load-bearing for the project.

## Top-level

- [Key concepts](https://www.chezmoi.io/reference/concepts/)
- [Source state attributes](https://www.chezmoi.io/reference/source-state-attributes/) — captured at `source-state-attributes.md`
- [Target types](https://www.chezmoi.io/reference/target-types/)
- [Application order of changes](https://www.chezmoi.io/reference/application-order/)
- [Configuration file](https://www.chezmoi.io/reference/configuration-file/)
- [Special files](https://www.chezmoi.io/reference/special-files/)
- [Special directories](https://www.chezmoi.io/reference/special-directories/)
- [Command line flags](https://www.chezmoi.io/reference/command-line-flags/)
- [Commands](https://www.chezmoi.io/reference/commands/)
- [Templates](https://www.chezmoi.io/reference/templates/)
- [Variables](https://www.chezmoi.io/reference/templates/variables/)
- [Directives](https://www.chezmoi.io/reference/templates/directives/)
- [Functions](https://www.chezmoi.io/reference/templates/functions/)
- [Plugins](https://www.chezmoi.io/reference/plugins/)
- [Release history](https://www.chezmoi.io/reference/release-history/)

## Configuration File

- [Variables](https://www.chezmoi.io/reference/configuration-file/variables/)
- [Editor](https://www.chezmoi.io/reference/configuration-file/editor/)
- [Hooks](https://www.chezmoi.io/reference/configuration-file/hooks/)
- [Interpreters](https://www.chezmoi.io/reference/configuration-file/interpreters/)
- [pinentry](https://www.chezmoi.io/reference/configuration-file/pinentry/)
- [textconv](https://www.chezmoi.io/reference/configuration-file/textconv/)
- [umask](https://www.chezmoi.io/reference/configuration-file/umask/)
- [Warnings](https://www.chezmoi.io/reference/configuration-file/warnings/)

## Special Files

- [`.chezmoi.<format>.tmpl`](https://www.chezmoi.io/reference/special-files/chezmoi-format-tmpl/)
- [`.chezmoidata.<format>`](https://www.chezmoi.io/reference/special-files/chezmoidata-format/)
- [`.chezmoiexternal.<format>`](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/) — captured at `chezmoiexternal.md`
- [`.chezmoiignore`](https://www.chezmoi.io/reference/special-files/chezmoiignore/)
- [`.chezmoiremove`](https://www.chezmoi.io/reference/special-files/chezmoiremove/)
- [`.chezmoiroot`](https://www.chezmoi.io/reference/special-files/chezmoiroot/)
- [`.chezmoiversion`](https://www.chezmoi.io/reference/special-files/chezmoiversion/)

## Special Directories

- [`.chezmoidata/`](https://www.chezmoi.io/reference/special-directories/chezmoidata/)
- [`.chezmoiexternals/`](https://www.chezmoi.io/reference/special-directories/chezmoiexternals/)
- [`.chezmoiscripts/`](https://www.chezmoi.io/reference/special-directories/chezmoiscripts/)
- [`.chezmoitemplates/`](https://www.chezmoi.io/reference/special-directories/chezmoitemplates/)

## Command Line Flags

- [Global](https://www.chezmoi.io/reference/command-line-flags/global/)
- [Common](https://www.chezmoi.io/reference/command-line-flags/common/)
- [Developer](https://www.chezmoi.io/reference/command-line-flags/developer/)

## Commands

`add`, `age`, `age-keygen`, `apply`, `archive`, `cat`, `cat-config`, `cd`,
`chattr`, `completion`, `data`, `decrypt`, `destroy`, `diff`, `docker`,
`doctor`, `dump`, `dump-config`, `edit`, `edit-config`,
`edit-config-template`, `edit-encrypted`, `encrypt`, `execute-template`,
`forget`, `generate`, `git`, `help`, `ignored`, `import`, `init`,
`license`, `list`, `manage`, `managed`, `merge`, `merge-all`, `podman`,
`purge`, `re-add`, `remove`, `rm`, `secret`, `source-path`, `ssh`,
`state`, `status`, `target-path`, `unmanage`, `unmanaged`, `update`,
`upgrade`, `verify`. Each lives at
`https://www.chezmoi.io/reference/commands/<name>/`.

## Templates

### Functions (general-purpose)

`abortEmpty`, `comment`, `completion`, `decrypt`, `deleteValueAtPath`,
`encrypt`, `ensureLinePrefix`, `eqFold`, `exec`, `findExecutable`,
`findOneExecutable`, `fromIni`, `fromJson`, `fromJsonc`, `fromToml`,
`fromYaml`, `getRedirectedURL`, `glob`, `globCaseInsensitive`,
`hexDecode`, `hexEncode`, `include`, `includeTemplate`, `ioreg`,
`isExecutable`, `joinPath`, `jq`, `lookPath`, `lstat`,
`mozillaInstallHash`, `output`, `outputList`, `pruneEmptyDicts`,
`quoteList`, `replaceAllRegex`, `setValueAtPath`, `stat`, `stdinIsATTY`,
`toIni`, `toPrettyJson`, `toString`, `toStrings`, `toToml`, `toYaml`,
`warnf`. Each lives at
`https://www.chezmoi.io/reference/templates/functions/<name>/`.

### GitHub functions

`gitHubKeys`, `gitHubLatestRelease`, `gitHubRelease`,
`gitHubLatestReleaseAssetURL`, `gitHubReleaseAssetURL`, `gitHubLatestTag`,
`gitHubReleases`, `gitHubTags` — under
`https://www.chezmoi.io/reference/templates/github-functions/`.

### Init functions

`exit`, `promptBool`, `promptBoolOnce`, `promptChoice`, `promptChoiceOnce`,
`promptInt`, `promptIntOnce`, `promptMultichoice`, `promptMultichoiceOnce`,
`promptString`, `promptStringOnce`, `writeToStdout` — under
`https://www.chezmoi.io/reference/templates/init-functions/`.

### Password manager functions

1Password, AWS Secrets Manager, Azure Key Vault, Bitwarden (incl. `rbw`),
Dashlane, Doppler, ejson, gopass, KeePassXC, Keeper, Keyring, LastPass,
pass, Passhole, Proton Pass, Vault, plus generic `secret` / `secretJSON`
— each under `https://www.chezmoi.io/reference/templates/<provider>-functions/`.

This project does not use chezmoi's password-manager template helpers
because secrets flow through sops-nix instead. See the
[sec-sops-encrypt](../../sec-sops-encrypt/SKILL.md) skill.
